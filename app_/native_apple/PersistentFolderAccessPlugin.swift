import Foundation
#if os(macOS)
import Cocoa
import FlutterMacOS
#else
import Flutter
import UIKit
import UniformTypeIdentifiers
#endif

/// Bookmarks are returned to the account-encrypted Dart configuration. They
/// are never written to UserDefaults, logs, or shared with another process.
final class PersistentFolderAccessPlugin: NSObject, FlutterPlugin {
  private var pending: FlutterResult?
  private var leases: [String: URL] = [:]
  private static let maximumBookmarkBytes = 65536

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: "ronikcloud/folder-access", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(PersistentFolderAccessPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      guard pending == nil else { fail("busy", result); return }
      pending = result
      pick()
    case "acquire":
      guard let args = call.arguments as? [String: Any],
        let encoded = args["bookmark"] as? String, encoded.count <= 90000,
        let data = Data(base64Encoded: encoded), !data.isEmpty,
        data.count <= Self.maximumBookmarkBytes,
        let path = args["path"] as? String, path.hasPrefix("/"), !path.contains("\0"),
        leases.count < 64 else { fail("access-required", result); return }
      do {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options,
          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.isFileURL,
          url.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path,
          url.startAccessingSecurityScopedResource() else {
          fail("access-required", result); return
        }
        do {
          guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            url.stopAccessingSecurityScopedResource(); fail("access-required", result); return
          }
          let id = UUID().uuidString
          leases[id] = url
          result(id)
        } catch {
          url.stopAccessingSecurityScopedResource()
          fail("access-required", result)
        }
      } catch { fail("access-required", result) }
    case "release":
      guard let id = call.arguments as? String else { fail("invalid", result); return }
      if let url = leases.removeValue(forKey: id) { url.stopAccessingSecurityScopedResource() }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func pick() {
    #if os(macOS)
    let panel = NSOpenPanel()
    panel.title = "Select a folder to back up"
    panel.prompt = "Allow folder backup"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.begin { [weak self] response in
      self?.completeSelection(response == .OK ? panel.url : nil)
    }
    #else
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      finishError("picker-unavailable"); return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
    #endif
  }

  fileprivate func completeSelection(_ selected: URL?) {
    guard let url = selected else { finish(nil); return }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    do {
      guard url.isFileURL,
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
        finishError("access-required"); return
      }
      #if os(macOS)
      let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
      #else
      let options: URL.BookmarkCreationOptions = []
      #endif
      let data = try url.bookmarkData(options: options,
        includingResourceValuesForKeys: nil, relativeTo: nil)
      guard !data.isEmpty, data.count <= Self.maximumBookmarkBytes else {
        finishError("access-required"); return
      }
      finish(["path": url.standardizedFileURL.path,
        "bookmark": data.base64EncodedString(), "name": url.lastPathComponent])
    } catch { finishError("access-required") }
  }

  private func fail(_ code: String, _ result: FlutterResult) {
    result(FlutterError(code: code, message: "Choose the folder again to allow backup access.", details: nil))
  }
  private func finishError(_ code: String) {
    let result = pending; pending = nil
    if let result = result { fail(code, result) }
  }
  private func finish(_ value: Any?) {
    let result = pending; pending = nil; result?(value)
  }
  deinit { for url in leases.values { url.stopAccessingSecurityScopedResource() } }
}

#if os(iOS)
extension PersistentFolderAccessPlugin: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    completeSelection(urls.count == 1 ? urls[0] : nil)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completeSelection(nil) }
}
#endif
