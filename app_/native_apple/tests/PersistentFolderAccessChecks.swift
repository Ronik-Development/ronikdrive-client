import Foundation
import FlutterMacOS

@main
struct PersistentFolderAccessChecks {
  static func main() throws {
    let plugin = PersistentFolderAccessPlugin()
    func invoke(_ method: String, _ arguments: Any?) throws -> Any? {
      var called = false
      var response: Any?
      plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
        called = true
        response = $0
      }
      guard called else { throw failure("Native request did not complete") }
      return response
    }
    func deny(_ arguments: Any?) throws {
      guard let error = try invoke("acquire", arguments) as? FlutterError,
        error.code == "access-required" else {
        throw failure("Invalid folder grant was accepted")
      }
    }

    try deny(nil)
    try deny(["path": "/chosen", "bookmark": ""])
    try deny(["path": "/chosen", "bookmark": "invalid-base64"])
    try deny(["path": "/chosen", "bookmark": String(repeating: "A", count: 90001)])
    try deny(["path": "relative", "bookmark": "AQ=="])
    try deny(["path": "/chosen\0other", "bookmark": "AQ=="])
    try deny(["path": "/chosen", "bookmark": Data("not a bookmark".utf8).base64EncodedString()])

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("folder-access-check-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bookmark = try directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    try deny(["path": directory.appendingPathComponent("other").path,
      "bookmark": bookmark.base64EncodedString()])
    guard try invoke("release", "unknown-lease") == nil,
      try invoke("release", "unknown-lease") == nil else {
      throw failure("Lease release must be idempotent")
    }
    print("Native folder access: malformed, stale-context and mismatched grants rejected; repeated release passed.")
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "FolderAccessChecks", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
