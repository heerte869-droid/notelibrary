import Foundation
import SQLite3
import CryptoKit
import AppKit
import Security

final class LibraryDatabase {
    let root: URL
    let assetsURL: URL
    let workspaceURL: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(root: URL) throws {
        self.root = root
        assetsURL = root.appendingPathComponent("Assets", isDirectory: true)
        workspaceURL = root.appendingPathComponent("AI Workspace", isDirectory: true)
        for url in [root, assetsURL, workspaceURL, root.appendingPathComponent("Snapshots", isDirectory: true)] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        guard sqlite3_open_v2(root.appendingPathComponent("Library.sqlite").path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw AppFailure(message: "无法打开资料库。请检查保存位置是否可写。")
        }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
        sqlite3_finalize(statement)
        guard version <= 1 else { throw AppFailure(message: "这份资料库由更新版本创建，请先更新应用。") }
        try execute("CREATE TABLE IF NOT EXISTS library (id INTEGER PRIMARY KEY CHECK (id=1), payload BLOB NOT NULL)")
        try execute("PRAGMA user_version=1")
    }
    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw AppFailure(message: "资料库操作失败：\(String(cString: sqlite3_errmsg(db)))")
        }
    }
    func load() throws -> LibraryState {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM library WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw AppFailure(message: "资料库读取失败。") }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return LibraryState() }
        guard result == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { throw AppFailure(message: "资料库内容无法读取，请恢复备份。") }
        let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0)))
        let state = try JSONCoding.decoder.decode(LibraryState.self, from: data)
        guard state.schemaVersion == 1 else { throw AppFailure(message: "资料格式需要更新的应用版本。") }
        return state
    }
    func save(_ state: LibraryState, snapshot: Bool = false, forceSnapshot: Bool = false) throws {
        let data = try JSONCoding.encoder.encode(state)
        if snapshot, state.settings.automaticSnapshots || forceSnapshot {
            let previous = try load()
            let snapshotURL = root.appendingPathComponent("Snapshots/\(Date().timeIntervalSince1970)-\(makeID()).json")
            try JSONCoding.encoder.encode(previous).write(to: snapshotURL, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Snapshots"), includingPropertiesForKeys: nil).sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in files.dropFirst(40) { try? FileManager.default.removeItem(at: old) }
        }
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO library(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw AppFailure(message: "无法准备保存操作。") }
            defer { sqlite3_finalize(statement) }
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(data.count), transient) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw AppFailure(message: "保存失败，原有笔记已保留。") }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    func importImage(_ url: URL, existing: [SourceAsset], generated: Bool = false) throws -> SourceAsset {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 30_000_000, ImagePipeline.isReadable(data) else { throw AppFailure(message: "请选择有效图片，单张不超过 30 MB。") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let asset = existing.first(where: { $0.digest == digest && $0.generated == generated }) { return asset }
        let ext = url.pathExtension.lowercased()
        let safeExtension = ["png", "jpg", "jpeg", "heic", "webp", "tif", "tiff", "gif"].contains(ext) ? ext : "png"
        var asset = SourceAsset(filename: "", displayName: url.lastPathComponent, digest: digest, generated: generated)
        asset.filename = "\(asset.id).\(safeExtension)"
        try data.write(to: assetsURL.appendingPathComponent(asset.filename), options: .atomic)
        return asset
    }
    func importSource(_ url: URL, existing: [SourceAsset], control: SourceImportControl? = nil) throws -> SourceAsset {
        try control?.checkCancellation()
        let data = try SourceImport.readData(url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Task.checkCancellation(); try control?.checkCancellation()
        let ext = SourceImport.actualExtension(data, declared: url.pathExtension.lowercased())
        if var asset = existing.first(where: { $0.digest == digest && !$0.generated }) {
            if SourceImport.documentExtensions.contains(ext), asset.document?.extractionVersion != SourceImport.extractionVersion {
                asset.document = try SourceImport.document(data, extension: ext, control: control)
                asset.filename = asset.id + "." + ext
                asset.byteCount = data.count
            }
            if !FileManager.default.fileExists(atPath: assetURL(asset).path) { try data.write(to: assetURL(asset), options: .atomic) }
            return asset
        }
        let document = try SourceImport.document(data, extension: ext, control: control)
        var asset = SourceAsset(filename: "", displayName: url.lastPathComponent, digest: digest)
        asset.filename = "\(asset.id).\(ext)"
        asset.byteCount = data.count; asset.document = document
        try Task.checkCancellation()
        try data.write(to: assetURL(asset), options: .atomic)
        return asset
    }
    /// Re-read old extraction only when that source is used, off the interface thread.
    func refreshedSource(_ asset: SourceAsset) throws -> SourceAsset {
        guard !asset.generated else { return asset }
        let legacyPDF = asset.document == nil && (asset.displayName as NSString).pathExtension.lowercased() == "pdf"
        guard legacyPDF || (asset.document != nil && asset.document?.extractionVersion != SourceImport.extractionVersion) else { return asset }
        let url = assetURL(asset)
        // Old image import accepted PDFs while assigning a .png filename. Confirm bytes.
        if legacyPDF {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            guard try handle.read(upToCount: 5) == Data("%PDF-".utf8) else { return asset }
        }
        return try importSource(url, existing: [asset])
    }
    /// Only remove the superseded internal copy after metadata has committed successfully.
    func removeSupersededOriginal(_ old: SourceAsset, replacedBy updated: SourceAsset) {
        guard old.id == updated.id, old.digest == updated.digest, old.filename != updated.filename,
              let bytes = try? Data(contentsOf: assetURL(updated), options: .mappedIfSafe),
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == old.digest else { return }
        try? FileManager.default.removeItem(at: assetURL(old))
    }
    func assetURL(_ asset: SourceAsset) -> URL { assetsURL.appendingPathComponent(asset.filename) }

    func exportBackup(_ state: LibraryState, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw AppFailure(message: "备份目标已经存在，请换一个名称。") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let folder = destination.appendingPathComponent("Assets", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONCoding.encoder.encode(state).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
            for asset in state.assets {
                try FileManager.default.copyItem(at: assetURL(asset), to: folder.appendingPathComponent(asset.filename))
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    func readBackup(from url: URL) throws -> LibraryState {
        let manifest = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let state = try JSONCoding.decoder.decode(LibraryState.self, from: manifest)
        guard state.schemaVersion == 1 else { throw AppFailure(message: "不支持的备份版本。") }
        var names = Set<String>()
        for asset in state.assets {
            guard !asset.filename.contains("/"), !asset.filename.contains("\\"), !asset.filename.hasPrefix("."), names.insert(asset.filename).inserted else { throw AppFailure(message: "备份内存在不合法的附件路径。") }
            let source = url.appendingPathComponent("Assets").appendingPathComponent(asset.filename)
            let data = try Data(contentsOf: source)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == asset.digest else { throw AppFailure(message: "备份中的附件校验不通过：\(asset.displayName)") }
        }
        for asset in state.assets {
            let source = url.appendingPathComponent("Assets").appendingPathComponent(asset.filename)
            let target = assetURL(asset)
            if FileManager.default.fileExists(atPath: target.path) {
                let digest = SHA256.hash(data: try Data(contentsOf: target)).map { String(format: "%02x", $0) }.joined()
                guard digest == asset.digest else { throw AppFailure(message: "备份附件与现有资料发生冲突，已停止恢复。") }
            } else { try FileManager.default.copyItem(at: source, to: target) }
        }
        return state
    }
}

/// Local credentials stay separate from note backups and exports. Empty entries prevent
/// removed credentials from being imported again from an older installation.
final class CredentialStore: @unchecked Sendable {
    struct Document: Codable { var version = 1; var keys: [String: String] = [:] }
    enum Failure: LocalizedError, Equatable {
        case legacyUnavailable, unreadable, unwritable
        var errorDescription: String? {
            switch self {
            case .legacyUnavailable: return "请在服务设置填写 API 密钥。"
            case .unreadable: return "本机密钥配置无法读取，原文件未改动。请检查文件权限或恢复备份。"
            case .unwritable: return "无法保存本机密钥，请检查资料库位置是否可写。原配置已保留。"
            }
        }
    }
    private static let processLock = NSRecursiveLock()
    private static let queue = DispatchQueue(label: "dev.notelibrary.credentials", qos: .userInitiated)
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("api-keys.json") }
    private let legacyRead: ((String) throws -> String)?
    init(root: URL, legacyRead: ((String) throws -> String)? = nil) {
        directory = root.appendingPathComponent("Credentials", isDirectory: true)
        self.legacyRead = legacyRead
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: directory.path) {
                let attributes = try fm.attributesOfItem(atPath: directory.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else { throw Failure.unreadable }
            } else { try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw Failure.unwritable }
            defer { close(fd) }
            guard flock(fd, LOCK_EX) == 0 else { throw Failure.unwritable }
            defer { flock(fd, LOCK_UN) }
            return try body()
        } catch let failure as Failure { throw failure }
        catch { throw Failure.unreadable }
    }
    private func document() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Document() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 4_000_000 else { throw Failure.unreadable }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            let result = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard result.version == 1 else { throw Failure.unreadable }
            return result
        } catch { throw Failure.unreadable }
    }
    private func write(_ value: Document) throws {
        let temp = directory.appendingPathComponent("." + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let data = try JSONEncoder().encode(value)
            let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw Failure.unwritable }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
            guard rename(temp.path, fileURL.path) == 0 else { throw Failure.unwritable }
        } catch { throw Failure.unwritable }
    }
    func localValue(_ id: String) throws -> String? { try locked { try document().keys[id] } }
    func readChecked(_ id: String) throws -> String {
        try locked {
            var values = try document()
            if let key = values.keys[id] { return key }
            guard let legacyRead else { return "" }
            let key: String
            do { key = try legacyRead(id) } catch { throw Failure.legacyUnavailable }
            values.keys[id] = key
            try write(values)
            return key
        }
    }
    func readAsync(_ id: String) async throws -> String {
        let pending = CredentialRead()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.install(continuation)
                Self.queue.async {
                    guard !pending.isFinished else { return }
                    pending.finish(Result { try self.readChecked(id) })
                }
            }
        } onCancel: { pending.finish(.failure(CancellationError())) }
    }
    func set(_ value: String, for id: String) throws { try restoreLocalValue(value.trimmingCharacters(in: .whitespacesAndNewlines), for: id) }
    /// Only rollback removes an absent entry. User removal writes an explicit empty entry.
    func restoreLocalValue(_ value: String?, for id: String) throws {
        try locked {
            var values = try document()
            values.keys[id] = value
            try write(values)
        }
    }
}

/// One-time noninteractive migration. A denied legacy read can be replaced with an API key.
enum LegacyCredentialReader {
    private static let lock = NSLock()
    static func read(_ id: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        var previous: DarwinBoolean = true
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { throw CredentialStore.Failure.legacyUnavailable }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.notelibrary.api", kSecAttrAccount as String: id,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return try decodeReadResult(status: status, data: item as? Data)
    }
    static func decodeReadResult(status: OSStatus, data: Data?) throws -> String {
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data, let key = String(data: data, encoding: .utf8) else { throw CredentialStore.Failure.legacyUnavailable }
        return key
    }
}

/// A closed editor ignores a late credential read and resumes cancellation immediately.
final class CredentialRead: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    var isFinished: Bool { lock.withLock { result != nil } }
    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let waiting = continuation; continuation = nil
        lock.unlock()
        waiting?.resume(with: result)
    }
}
