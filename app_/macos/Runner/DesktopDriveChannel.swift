import Cocoa
import FileProvider
import FlutterMacOS

@available(macOS 11.0, *)
final class DesktopDriveChannel {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ronikcloud/desktop-drive", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
        let id = args["domain"] as? String,
        id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid", message: "Invalid drive configuration.", details: nil)); return
      }
      let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "RonikCloud")
      do {
        switch call.method {
        case "start", "heartbeat":
          guard let port = args["port"] as? Int, let token = args["token"] as? String else { throw DriveConnection.failure() }
          try DriveConnection.save(domain: id, port: port, token: token)
          if call.method == "start" {
            NSFileProviderManager.add(domain) { error in
              DispatchQueue.main.async {
                if error != nil {
                  try? DriveConnection.remove(domain: id)
                  result(FlutterError(code: "unavailable", message: "Finder integration could not start.", details: nil))
                } else { result(nil) }
              }
            }
          } else {
            NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
            result(nil)
          }
        case "stop":
          // Revokes NEW access. Existing local copies are not claimed erased.
          try DriveConnection.remove(domain: id)
          result(nil)
        case "disconnect":
          try DriveConnection.remove(domain: id)
          // Do not remove the domain: pending local changes must not be lost.
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "unavailable", message: "Unlock the device and retry drive setup.", details: nil))
      }
    }
  }
}
