import FileProvider
import UniformTypeIdentifiers
import CryptoKit
import Security

private let contentLimit = 64 * 1024 * 1024

private final class DriveItem: NSObject, NSFileProviderItem {
  let value: [String: Any]
  init(_ value: [String: Any]) throws {
    guard let id = value["id"] as? String, !id.isEmpty,
      let parent = value["parentId"] as? String, !parent.isEmpty,
      let name = value["name"] as? String, !name.isEmpty,
      !name.contains("/"), name != ".", name != "..",
      value["version"] is String, value["directory"] is Bool,
      let size = value["size"] as? Int, size >= 0 else {
      throw NSFileProviderError(.cannotSynchronize)
    }
    self.value = value
    super.init()
  }
  var itemIdentifier: NSFileProviderItemIdentifier {
    value["id"] as! String == "root" ? .rootContainer : NSFileProviderItemIdentifier(value["id"] as! String)
  }
  var parentItemIdentifier: NSFileProviderItemIdentifier {
    let id = value["parentId"] as! String
    return id == "root" ? .rootContainer : NSFileProviderItemIdentifier(id)
  }
  var filename: String { value["name"] as! String }
  var contentType: UTType { (value["directory"] as! Bool) ? .folder : (UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data) }
  var documentSize: NSNumber? { NSNumber(value: value["size"] as! Int) }
  var itemVersion: NSFileProviderItemVersion {
    let version = Data((value["version"] as! String).utf8)
    return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
  }
  var capabilities: NSFileProviderItemCapabilities {
    (value["directory"] as! Bool)
      ? [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming]
      : [.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting, .allowsDeleting]
  }
}

@available(macOS 12.0, *)
private final class Broker: NSObject, URLSessionTaskDelegate {
  let domain: String
  init(_ domain: String) { self.domain = domain }
  // Redirects could disclose the local bearer token. Never follow one.
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  func call(_ operation: String, _ payload: [String: Any]) async throws -> Data {
    let (port, token) = try DriveConnection.read(domain: domain)
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 60
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/\(operation)")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (bytes, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw NSFileProviderError(.serverUnreachable) }
    switch http.statusCode {
    case 200: break
    case 401: throw NSFileProviderError(.notAuthenticated)
    case 404: throw NSFileProviderError(.noSuchItem)
    case 409: throw NSFileProviderError(.cannotSynchronize)
    case 413: throw NSFileProviderError(.insufficientQuota)
    default: throw NSFileProviderError(.serverUnreachable)
    }
    guard bytes.count <= contentLimit else { throw NSFileProviderError(.cannotSynchronize) }
    // Keychain/session expiry is checked again before disclosing any result.
    let (_, currentToken) = try DriveConnection.read(domain: domain)
    guard token == currentToken else { throw NSFileProviderError(.notAuthenticated) }
    return bytes
  }
  func item(_ operation: String, _ payload: [String: Any]) async throws -> DriveItem {
    guard let object = try JSONSerialization.jsonObject(with: await call(operation, payload)) as? [String: Any] else {
      throw NSFileProviderError(.cannotSynchronize)
    }
    return try DriveItem(object)
  }
}

@available(macOS 12.0, *)
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
  private let domain: NSFileProviderDomain
  private let broker: Broker
  required init(domain: NSFileProviderDomain) {
    self.domain = domain
    self.broker = Broker(domain.identifier.rawValue)
    super.init()
  }
  func invalidate() {}
  private func id(_ value: NSFileProviderItemIdentifier) -> String {
    value == .rootContainer ? "root" : value.rawValue
  }
  func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
    run({ try await self.broker.item("item", ["id": self.id(identifier)]) }, completionHandler)
  }
  func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version: NSFileProviderItemVersion?,
    request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let task = Task {
      var temporary: URL?
      do {
        let item = try await broker.item("item", ["id": id(itemIdentifier)])
        if let version = version, version != item.itemVersion { throw NSFileProviderError(.cannotSynchronize) }
        let contents = try await broker.call("read", ["id": id(itemIdentifier), "version": item.value["version"]!])
        try Task.checkCancellation()
        guard let manager = NSFileProviderManager(for: domain) else { throw NSFileProviderError(.cannotSynchronize) }
        let url = try manager.temporaryDirectoryURL().appendingPathComponent(UUID().uuidString)
        temporary = url
        // This is the consented OS handoff; no original filename in staging.
        try contents.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try Task.checkCancellation()
        _ = try DriveConnection.read(domain: domain.identifier.rawValue)
        progress.completedUnitCount = 1
        completionHandler(url, item, nil)
        temporary = nil // File Provider owns the successful handoff.
      } catch {
        if let temporary = temporary { try? FileManager.default.removeItem(at: temporary) }
        completionHandler(nil, nil, error)
      }
    }
    progress.cancellationHandler = { task.cancel() }
    return progress
  }
  func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields,
    contents: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    run({
      guard itemTemplate.contentType != .symbolicLink && itemTemplate.contentType != .aliasFile else {
        throw NSFileProviderError(.cannotSynchronize)
      }
      var payload: [String: Any] = ["parentId": self.id(itemTemplate.parentItemIdentifier),
        "requestId": itemTemplate.itemIdentifier.rawValue,
        "name": itemTemplate.filename, "directory": itemTemplate.contentType == .folder]
      if let contents = contents { payload["contents"] = try self.readUpload(contents).base64EncodedString() }
      return try await self.broker.item("create", payload)
    }) { item, error in
      let handled: NSFileProviderItemFields = [.filename, .parentItemIdentifier, .contents]
      completionHandler(item, fields.subtracting(handled), false, error)
    }
  }
  func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion,
    changedFields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderModifyItemOptions,
    request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    run({
      guard let version = String(data: baseVersion.metadataVersion, encoding: .utf8) else { throw NSFileProviderError(.cannotSynchronize) }
      var payload: [String: Any] = ["id": self.id(item.itemIdentifier), "version": version]
      if changedFields.contains(.filename) { payload["name"] = item.filename }
      if changedFields.contains(.parentItemIdentifier) { payload["parentId"] = self.id(item.parentItemIdentifier) }
      if changedFields.contains(.contents) && contents == nil {
        throw NSFileProviderError(.cannotSynchronize)
      }
      if let contents = contents { payload["contents"] = try self.readUpload(contents).base64EncodedString() }
      return try await self.broker.item("update", payload)
    }) { result, error in
      let handled: NSFileProviderItemFields = [.filename, .parentItemIdentifier, .contents]
      completionHandler(result, changedFields.subtracting(handled), false, error)
    }
  }
  func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest,
    completionHandler: @escaping (Error?) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let task = Task {
      do {
        guard let version = String(data: baseVersion.metadataVersion, encoding: .utf8) else { throw NSFileProviderError(.cannotSynchronize) }
        _ = try await broker.call("recycle", ["id": id(identifier), "version": version])
        progress.completedUnitCount = 1
        completionHandler(nil)
      } catch { completionHandler(error) }
    }
    progress.cancellationHandler = { task.cancel() }
    return progress
  }
  func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
    DriveEnumerator(broker: broker, parent: containerItemIdentifier == .workingSet ? "working-set" : id(containerItemIdentifier))
  }
  private func readUpload(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let contents = try handle.read(upToCount: contentLimit + 1) ?? Data()
    guard contents.count <= contentLimit else { throw NSFileProviderError(.insufficientQuota) }
    return contents
  }
  private func run(_ work: @escaping () async throws -> DriveItem,
    _ completion: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let task = Task {
      do {
        try Task.checkCancellation()
        let item = try await work()
        try Task.checkCancellation()
        progress.completedUnitCount = 1
        completion(item, nil)
      } catch { completion(nil, error) }
    }
    progress.cancellationHandler = { task.cancel() }
    return progress
  }
}

@available(macOS 12.0, *)
private final class DriveEnumerator: NSObject, NSFileProviderEnumerator {
  let broker: Broker
  let parent: String
  init(broker: Broker, parent: String) { self.broker = broker; self.parent = parent }
  private let stateLock = NSLock()
  private var ended = false
  private var initial: Task<([DriveItem], Data), Error>?
  func invalidate() {
    stateLock.lock()
    ended = true
    let task = initial
    stateLock.unlock()
    task?.cancel()
  }
  private func checkActive() throws {
    stateLock.lock()
    let active = !ended
    stateLock.unlock()
    guard active else { throw NSFileProviderError(.cannotSynchronize) }
    _ = try DriveConnection.read(domain: broker.domain)
  }
  private func initialSnapshot() throws -> Task<([DriveItem], Data), Error> {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard !ended else { throw NSFileProviderError(.cannotSynchronize) }
    if let initial = initial { return initial }
    let task = Task { () throws -> ([DriveItem], Data) in
      let items = try await self.currentItems()
      let values = Dictionary(uniqueKeysWithValues: items.map { ($0.itemIdentifier.rawValue, $0.value["version"] as! String) })
      let anchor = try await DriveChangeSnapshots.shared.save(domain: self.broker.domain, parent: self.parent, values: values)
      try Task.checkCancellation()
      return (items, anchor)
    }
    initial = task
    return task
  }
  func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
    Task {
      do {
        let (items, _) = try await initialSnapshot().value
        try checkActive()
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
      } catch { observer.finishEnumeratingWithError(error) }
    }
  }
  func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
    Task {
      do {
        let old = try await DriveChangeSnapshots.shared.load(domain: broker.domain, parent: parent, anchor: syncAnchor.rawValue)
        let rows = try await currentItems()
        let current = Dictionary(uniqueKeysWithValues: rows.map { ($0.itemIdentifier.rawValue, $0.value["version"] as! String) })
        var removed: [NSFileProviderItemIdentifier] = []
        for identifier in old.keys where current[identifier] == nil {
          // A listing is not proof of deletion: confirm each missing item,
          // including moves out of this particular enumerated directory.
          do {
            let item = try await broker.item("item", ["id": identifier])
            if parent != "working-set" && item.value["parentId"] as? String != parent {
              removed.append(NSFileProviderItemIdentifier(identifier))
            } else { throw NSFileProviderError(.cannotSynchronize) }
          } catch let error as NSError where error.domain == NSFileProviderErrorDomain && error.code == NSFileProviderError.Code.noSuchItem.rawValue {
            removed.append(NSFileProviderItemIdentifier(identifier))
          }
        }
        let anchor = try await DriveChangeSnapshots.shared.save(domain: broker.domain, parent: parent, values: current)
        try checkActive()
        observer.didUpdate(rows.filter { old[$0.itemIdentifier.rawValue] != $0.value["version"] as? String })
        observer.didDeleteItems(withIdentifiers: removed)
        observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(anchor), moreComing: false)
      } catch { observer.finishEnumeratingWithError(error) }
    }
  }
  private func currentItems() async throws -> [DriveItem] {
    let data = try await broker.call("list", ["parentId": parent])
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = object["items"] as? [[String: Any]], rows.count <= 10000 else { throw NSFileProviderError(.cannotSynchronize) }
    let items = try rows.map { try DriveItem($0) }
    guard Set(items.map { $0.itemIdentifier }).count == items.count else { throw NSFileProviderError(.cannotSynchronize) }
    return items
  }
  func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
    Task {
      do {
        let (_, anchor) = try await initialSnapshot().value
        try checkActive()
        completionHandler(NSFileProviderSyncAnchor(anchor))
      } catch { completionHandler(nil) }
    }
  }
}

/// Encrypted, bounded change baselines survive extension/process restarts.
/// This is disposable synchronization metadata, never a store of file contents.
@available(macOS 12.0, *)
actor DriveChangeSnapshots {
  static let shared = DriveChangeSnapshots()
  private func context(_ domain: String, _ parent: String) -> Data { Data((domain + "\n" + parent).utf8) }
  private func directory() throws -> URL {
    let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RonikDriveChangeSnapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return url
  }
  private func key() throws -> SymmetricKey {
    var query = try DriveConnection.query("change-snapshot-key")
    query[kSecAttrService as String] = "com.ronikcloud.desktop-drive.change-key.v1"
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
    guard status == errSecItemNotFound else { throw DriveConnection.failure() }
    let created = SymmetricKey(size: .bits256)
    query[kSecValueData as String] = created.withUnsafeBytes { Data($0) }
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let added = SecItemAdd(query as CFDictionary, nil)
    if added == errSecDuplicateItem { return try key() }
    guard added == errSecSuccess else { throw DriveConnection.failure() }
    return created
  }
  func save(domain: String, parent: String, values: [String: String]) throws -> Data {
    let plain = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    guard plain.count <= 4 * 1024 * 1024 else { throw NSFileProviderError(.cannotSynchronize) }
    let aad = context(domain, parent)
    let digest = SHA256.hash(data: aad + plain).map { String(format: "%02x", $0) }.joined()
    let sealed = try AES.GCM.seal(plain, using: key(), authenticating: aad)
    guard let data = sealed.combined else { throw NSFileProviderError(.cannotSynchronize) }
    let root = try directory()
    let target = root.appendingPathComponent(digest)
    try data.write(to: target, options: .atomic)
    // Bound the disposable cache; an evicted anchor triggers full enumeration.
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
      .filter { $0.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
      .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    for stale in files.dropFirst(64) where stale != target { try? FileManager.default.removeItem(at: stale) }
    return Data(digest.utf8)
  }
  func load(domain: String, parent: String, anchor: Data) throws -> [String: String] {
    guard let digest = String(data: anchor, encoding: .utf8), digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NSFileProviderError(.syncAnchorExpired) }
    let url = try directory().appendingPathComponent(digest)
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024 + 64,
      let encrypted = try? Data(contentsOf: url) else { throw NSFileProviderError(.syncAnchorExpired) }
    do {
      let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key(), authenticating: context(domain, parent))
      guard let values = try JSONSerialization.jsonObject(with: plain) as? [String: String], values.count <= 10000 else { throw NSFileProviderError(.syncAnchorExpired) }
      return values
    } catch { throw NSFileProviderError(.syncAnchorExpired) }
  }
}
