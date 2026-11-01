import Cocoa
import FlutterMacOS
import ServiceManagement

private let backgroundBackupWorkerArgument = "--background-backup-worker"

class MainFlutterWindow: NSWindow {
  private var desktopDrive: AnyObject?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    PersistentFolderAccessPlugin.register(with:
      flutterViewController.registrar(forPlugin: "PersistentFolderAccessPlugin"))
    if #available(macOS 12.0, *) {
      desktopDrive = DesktopDriveChannel(messenger: flutterViewController.engine.binaryMessenger)
    }

    let startupChannel = FlutterMethodChannel(
      name: "ronikcloud/startup", binaryMessenger: flutterViewController.engine.binaryMessenger)
    startupChannel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(FlutterError(code: "unsupported", message: "Use System Settings Login Items on this macOS version.", details: nil))
        return
      }
      switch call.method {
      case "isEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "setEnabled":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "invalid-argument", message: "Expected a boolean.", details: nil))
          return
        }
        do {
          if enabled { try SMAppService.mainApp.register() }
          else { try SMAppService.mainApp.unregister() }
          result(nil)
        } catch {
          result(FlutterError(code: "startup-unavailable", message: "Check Login Items in System Settings.", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    if ProcessInfo.processInfo.arguments.contains(backgroundBackupWorkerArgument) {
      title = "RonikCloud Background"
      orderOut(nil)
      NSApp.setActivationPolicy(.accessory)
    }
  }
}
