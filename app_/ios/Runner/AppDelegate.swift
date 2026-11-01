import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "PersistentFolderAccessPlugin") {
      PersistentFolderAccessPlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "PhotoLibraryPlugin") {
      PhotoLibraryPlugin.register(with: registrar)
    }
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(forPlugin: "PersistentFolderAccessPlugin") {
        PersistentFolderAccessPlugin.register(with: registrar)
      }
      if let registrar = registry.registrar(forPlugin: "PhotoLibraryPlugin") {
        PhotoLibraryPlugin.register(with: registrar)
      }
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "periodic-sync-task", frequency: NSNumber(value: 15 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
