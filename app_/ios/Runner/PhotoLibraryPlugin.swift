import Flutter
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Registered in both Flutter engines, including Workmanager's headless engine.
final class PhotoLibraryPlugin: NSObject, FlutterPlugin, PHPickerViewControllerDelegate {
  private var pickResult: FlutterResult?
  private static var exportRoot: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ronik-photo-exports", isDirectory: true)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ronikcloud/photo-library", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PhotoLibraryPlugin(), channel: channel)
    // Remove only our expired exports left by a terminated process.
    let fm = FileManager.default
    if let files = try? fm.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.creationDateKey]) {
      for file in files {
        if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
           Date().timeIntervalSince(date) > 24 * 60 * 60 {
          try? fm.removeItem(at: file)
        }
      }
    }
  }

  private func status() -> String {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized: return "authorized"
    case .limited: return "limited"
    case .notDetermined: return "notDetermined"
    default: return "denied"
    }
  }

  private func fail(_ result: @escaping FlutterResult, _ code: String) {
    result(FlutterError(code: code, message: "Photos operation unavailable.", details: nil))
  }

  private func presenter() -> UIViewController? {
    var controller = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
    while let next = controller?.presentedViewController { controller = next }
    return controller
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pick":
      guard pickResult == nil, let controller = presenter() else {
        fail(result, "photo_picker"); return
      }
      // PHPicker grants access only to the chosen items; no library permission.
      var configuration = PHPickerConfiguration()
      configuration.filter = .images
      configuration.selectionLimit = 0
      configuration.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      pickResult = result
      controller.present(picker, animated: true)
    case "status": result(status())
    case "authorize":
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
        DispatchQueue.main.async { result(self.status()) }
      }
    case "manageAccess":
      guard let controller = presenter() else { fail(result, "photo_access"); return }
      if status() == "limited" {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in result(nil) }
      } else if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url) { _ in result(nil) }
      } else { result(nil) }
    case "list":
      guard status() == "authorized" || status() == "limited" else {
        fail(result, "photo_access"); return
      }
      let offset = max(0, args["offset"] as? Int ?? 0)
      let limit = min(100, max(1, args["limit"] as? Int ?? 100))
      DispatchQueue.global(qos: .utility).async {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var values = [[String: Any]]()
        if offset < assets.count {
          for index in offset..<min(offset + limit, assets.count) {
            let asset = assets.object(at: index)
            let date = asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)
            values.append(["id": asset.localIdentifier, "modified": Int64(date.timeIntervalSince1970 * 1000)])
          }
        }
        DispatchQueue.main.async { result(values) }
      }
    case "export":
      guard status() == "authorized" || status() == "limited" else {
        fail(result, "photo_access"); return
      }
      guard let id = args["id"] as? String,
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
            asset.mediaType == .image else { fail(result, "photo_missing"); return }
      let modified = Int64((asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000)
      guard let expected = args["modified"] as? NSNumber, expected.int64Value == modified else {
        fail(result, "photo_changed"); return
      }
      // Preserve the original image resource without transcoding. Live Photo
      // motion and nondestructive edit instructions are outside this image backup.
      guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
        fail(result, "photo_export"); return
      }
      let fm = FileManager.default
      let directory = Self.exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      let rawExtension = (resource.originalFilename as NSString).pathExtension
      let ext = rawExtension.range(of: "^[A-Za-z0-9]{1,12}$", options: .regularExpression) == nil ? "image" : rawExtension
      let destination = directory.appendingPathComponent("image.\(ext)")
      do {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
      } catch { fail(result, "photo_export"); return }
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = true
      PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
        DispatchQueue.main.async {
          guard error == nil else {
            try? fm.removeItem(at: directory)
            self.fail(result, "photo_export"); return
          }
          // Permission and edits can change during an iCloud download.
          guard self.status() == "authorized" || self.status() == "limited",
                let current = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                Int64((current.modificationDate ?? current.creationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000) == modified else {
            try? fm.removeItem(at: directory)
            self.fail(result, "photo_changed"); return
          }
          result(["path": destination.path, "name": (resource.originalFilename as NSString).lastPathComponent])
        }
      }
    case "release":
      guard let path = args["path"] as? String else { fail(result, "photo_export"); return }
      let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let root = Self.exportRoot.standardizedFileURL.resolvingSymlinksInPath()
      let directory = file.deletingLastPathComponent()
      guard directory.deletingLastPathComponent() == root,
            UUID(uuidString: directory.lastPathComponent) != nil else {
        fail(result, "photo_export"); return
      }
      do {
        if FileManager.default.fileExists(atPath: directory.path) {
          try FileManager.default.removeItem(at: directory)
        }
        result(nil)
      } catch { fail(result, "photo_export"); }
    default: result(FlutterMethodNotImplemented)
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let completion = pickResult else { return }
    // Serialize copies so large selections do not decode or copy all images at once.
    copySelection(results, index: 0, files: [], completion: completion)
  }

  private func copySelection(_ selection: [PHPickerResult], index: Int,
                             files: [[String: String]], completion: @escaping FlutterResult) {
    if index == selection.count {
      pickResult = nil
      completion(files)
      return
    }
    let provider = selection[index].itemProvider
    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
      let fm = FileManager.default
      let directory = Self.exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        guard error == nil, let url = url else { throw NSError(domain: "Photos", code: 1) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = directory
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try excluded.setResourceValues(attributes)
        let destination = directory.appendingPathComponent("image").appendingPathExtension(url.pathExtension)
        try fm.copyItem(at: url, to: destination)
        let suggested = (provider.suggestedName ?? url.lastPathComponent) as NSString
        var name = suggested.lastPathComponent
        if (name as NSString).pathExtension.isEmpty && !url.pathExtension.isEmpty {
          name += "." + url.pathExtension
        }
        let updated = files + [["path": destination.path, "name": name]]
        DispatchQueue.main.async {
          self.copySelection(selection, index: index + 1, files: updated, completion: completion)
        }
      } catch {
        try? fm.removeItem(at: directory)
        for file in files {
          if let path = file["path"] {
            try? fm.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
          }
        }
        DispatchQueue.main.async {
          self.pickResult = nil
          self.fail(completion, "photo_export")
        }
      }
    }
  }
}
