import Foundation
import Security

// Shared only by the signed containing app and its File Provider extension.
// This credential authorizes the local broker, never the cloud account.
enum DriveConnection {
  static let service = "com.ronikcloud.desktop-drive.session.v1"
  static func query(_ domain: String) throws -> [String: Any] {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "DesktopDriveKeychainGroup") as? String,
          !group.isEmpty, !group.contains("$(") else { throw failure() }
    return [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: domain,
      kSecAttrAccessGroup as String: group,
      kSecUseDataProtectionKeychain as String: true]
  }
  static func save(domain: String, port: Int, token: String) throws {
    guard (1024...65535).contains(port), token.count == 44 else { throw failure() }
    let data = try JSONSerialization.data(withJSONObject:
      ["port": port, "token": token, "expires": Date().timeIntervalSince1970 + 90])
    let base = try query(domain)
    let fields: [String: Any] = [kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
    let status = SecItemUpdate(base as CFDictionary, fields as CFDictionary)
    if status == errSecItemNotFound {
      guard SecItemAdd(base.merging(fields) { _, next in next } as CFDictionary, nil) == errSecSuccess else { throw failure() }
    } else if status != errSecSuccess { throw failure() }
  }
  static func remove(domain: String) throws {
    let status = SecItemDelete(try query(domain) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
  }
  static func read(domain: String) throws -> (Int, String) {
    var q = try query(domain)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let port = value["port"] as? Int, (1024...65535).contains(port),
      let token = value["token"] as? String, token.count == 44,
      let expires = value["expires"] as? Double,
      expires > Date().timeIntervalSince1970 else { throw failure() }
    return (port, token)
  }
  static func failure() -> NSError {
    NSError(domain: "RonikCloudDrive", code: 401, userInfo: nil)
  }
}
