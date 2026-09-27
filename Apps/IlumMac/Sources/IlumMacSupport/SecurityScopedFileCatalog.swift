import Foundation
import IlumCore

public final class SecurityScopedFileCatalog: UserFileAccessBroker, @unchecked Sendable {
    private struct Record: Codable {
        let id: UserFileResourceID
        var displayName: String
        var locationHint: String
        var bookmarkData: Data
        var descriptor: UserFileDescriptor { UserFileDescriptor(id: id, displayName: displayName, locationHint: locationHint) }
    }
    private struct Store: Codable { var records: [Record] }
    private let storeURL: URL
    private let lock = NSLock()
    private var records: [UserFileResourceID: Record]

    public init(storeURL: URL) throws {
        self.storeURL = storeURL
        if FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                let data = try Data(contentsOf: storeURL)
                let store = try JSONDecoder().decode(Store.self, from: data)
                records = Dictionary(uniqueKeysWithValues: store.records.map { ($0.id, $0) })
            } catch { throw SecurityScopedFileCatalogError.invalidStore(String(describing: error)) }
        } else { records = [:] }
    }

    @discardableResult
    public func register(url: URL) throws -> UserFileDescriptor {
        let canonical = url.standardizedFileURL
        if let existing = lock.withLock({ records.values.first(where: { $0.locationHint == canonical.path }) }) { return existing.descriptor }
        let bookmark: Data
        do { bookmark = try canonical.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw SecurityScopedFileCatalogError.bookmarkCreationFailed(String(describing: error)) }
        let id = UserFileResourceID()
        let record = Record(id: id, displayName: canonical.lastPathComponent, locationHint: canonical.path, bookmarkData: bookmark)
        try lock.withLock {
            records[id] = record
            do { try persistLocked() } catch { records.removeValue(forKey: id); throw error }
        }
        return record.descriptor
    }

    public func remove(resourceID: UserFileResourceID) throws {
        try lock.withLock {
            let removed = records.removeValue(forKey: resourceID)
            do { try persistLocked() } catch { if let removed { records[resourceID] = removed }; throw error }
        }
    }

    public func allDescriptors() -> [UserFileDescriptor] {
        lock.withLock {
            records.values.map(\.descriptor).sorted {
                if $0.displayName == $1.displayName { return $0.id.rawValue < $1.id.rawValue }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    public func descriptor(for id: UserFileResourceID) throws -> UserFileDescriptor {
        guard let record = lock.withLock({ records[id] }) else { throw UserFileAccessError.unknownResource(id) }
        return record.descriptor
    }

    public func readText(resourceID: UserFileResourceID, maxBytes: Int) async throws -> UserFileTextRead {
        guard (1...16_777_216).contains(maxBytes) else { throw UserFileAccessError.invalidLimit }
        return try withSecurityScopedURL(resourceID: resourceID) { url, descriptor in
            let handle: FileHandle
            do { handle = try FileHandle(forReadingFrom: url) }
            catch { throw UserFileAccessError.resourceUnavailable(resourceID) }
            defer { try? handle.close() }
            let raw = try handle.read(upToCount: maxBytes + 1) ?? Data()
            let truncated = raw.count > maxBytes
            let data = truncated ? Data(raw.prefix(maxBytes)) : raw
            guard let content = String(data: data, encoding: .utf8) else { throw UserFileAccessError.notUTF8 }
            return UserFileTextRead(descriptor: descriptor, content: content, byteCount: data.count, truncated: truncated)
        }
    }

    func withSecurityScopedURL<T>(resourceID: UserFileResourceID, _ body: (URL, UserFileDescriptor) throws -> T) throws -> T {
        guard let record = lock.withLock({ records[resourceID] }) else { throw UserFileAccessError.unknownResource(resourceID) }
        var isStale = false
        let resolvedURL: URL
        do { resolvedURL = try URL(resolvingBookmarkData: record.bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) }
        catch { throw UserFileAccessError.resourceUnavailable(resourceID) }
        let started = resolvedURL.startAccessingSecurityScopedResource()
        defer { if started { resolvedURL.stopAccessingSecurityScopedResource() } }
        if isStale { try refreshBookmark(resourceID: resourceID, resolvedURL: resolvedURL) }
        return try body(resolvedURL, try descriptor(for: resourceID))
    }

    private func refreshBookmark(resourceID: UserFileResourceID, resolvedURL: URL) throws {
        let fresh: Data
        do { fresh = try resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw SecurityScopedFileCatalogError.bookmarkRefreshFailed(String(describing: error)) }
        try lock.withLock {
            guard var record = records[resourceID] else { throw UserFileAccessError.unknownResource(resourceID) }
            let previous = record
            record.bookmarkData = fresh
            record.displayName = resolvedURL.lastPathComponent
            record.locationHint = resolvedURL.standardizedFileURL.path
            records[resourceID] = record
            do { try persistLocked() } catch { records[resourceID] = previous; throw error }
        }
    }

    private func persistLocked() throws {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Store(records: Array(records.values))).write(to: storeURL, options: .atomic)
        } catch { throw SecurityScopedFileCatalogError.storeWriteFailed(String(describing: error)) }
    }
}

public enum SecurityScopedFileCatalogError: Error, CustomStringConvertible, Sendable {
    case invalidStore(String), bookmarkCreationFailed(String), bookmarkRefreshFailed(String), storeWriteFailed(String)
    public var description: String {
        switch self {
        case .invalidStore(let d): return "The Ilum user-file catalog could not be loaded: \(d)"
        case .bookmarkCreationFailed(let d): return "The selected file could not be registered securely: \(d)"
        case .bookmarkRefreshFailed(let d): return "The selected file bookmark could not be refreshed: \(d)"
        case .storeWriteFailed(let d): return "The Ilum user-file catalog could not be saved: \(d)"
        }
    }
}
