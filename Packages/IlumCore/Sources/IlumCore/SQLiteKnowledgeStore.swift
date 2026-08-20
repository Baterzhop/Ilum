import Foundation
import CSQLite

public enum KnowledgeStoreError: Error, CustomStringConvertible, Sendable, Equatable {
    case openFailed(String)
    case statementFailed(String)
    case executionFailed(String)
    case invalidRecord(String)
    case corruptData(String)

    public var description: String {
        switch self {
        case .openFailed(let m): return "Knowledge SQLite open failed: \(m)"
        case .statementFailed(let m): return "Knowledge SQLite statement failed: \(m)"
        case .executionFailed(let m): return "Knowledge SQLite execution failed: \(m)"
        case .invalidRecord(let m): return "Knowledge record is invalid: \(m)"
        case .corruptData(let m): return "Knowledge SQLite data is invalid: \(m)"
        }
    }
}

private final class KnowledgeSQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
    init(raw: OpaquePointer) { self.raw = raw }
    deinit { sqlite3_close_v2(raw) }
}

public actor SQLiteKnowledgeStore: KnowledgeStore {
    private let connection: KnowledgeSQLiteConnection

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            if let handle { sqlite3_close_v2(handle) }
            throw KnowledgeStoreError.openFailed(message)
        }
        do {
            try Self.execute(handle, sql: "PRAGMA foreign_keys = ON;")
            try Self.execute(handle, sql: "PRAGMA journal_mode = WAL;")
            try Self.execute(handle, sql: "PRAGMA synchronous = NORMAL;")
            try Self.execute(handle, sql: Self.schema)
            connection = KnowledgeSQLiteConnection(raw: handle)
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }
    }

    public func loadDocument(sourceResourceID: UserFileResourceID) async throws -> KnowledgeDocument? {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(db, sql: "SELECT id, source_resource_id, display_name, media_type, page_count, metadata_json, created_at, updated_at FROM knowledge_documents WHERE source_resource_id = ?1 LIMIT 1;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(sourceResourceID.rawValue, to: statement, index: 1)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return try decodeDocument(statement)
        case SQLITE_DONE: return nil
        default: throw KnowledgeStoreError.executionFailed(errorMessage(db))
        }
    }

    public func loadChunks(documentID: UUID) async throws -> [KnowledgeChunk] {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(db, sql: "SELECT id, document_id, ordinal, page_start, page_end, text FROM knowledge_chunks WHERE document_id = ?1 ORDER BY ordinal ASC;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(documentID.uuidString, to: statement, index: 1)
        var chunks: [KnowledgeChunk] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = UUID(uuidString: text(statement, column: 0)),
                      let storedDocumentID = UUID(uuidString: text(statement, column: 1)) else {
                    throw KnowledgeStoreError.corruptData("invalid chunk UUID")
                }
                chunks.append(KnowledgeChunk(
                    id: id, documentID: storedDocumentID,
                    ordinal: Int(sqlite3_column_int64(statement, 2)),
                    pageStart: Int(sqlite3_column_int64(statement, 3)),
                    pageEnd: Int(sqlite3_column_int64(statement, 4)),
                    text: text(statement, column: 5)
                ))
            case SQLITE_DONE: return chunks
            default: throw KnowledgeStoreError.executionFailed(errorMessage(db))
            }
        }
    }

    public func listDocuments() async throws -> [KnowledgeDocument] {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(db, sql: "SELECT id, source_resource_id, display_name, media_type, page_count, metadata_json, created_at, updated_at FROM knowledge_documents ORDER BY updated_at DESC, display_name ASC;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        var documents: [KnowledgeDocument] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: documents.append(try decodeDocument(statement))
            case SQLITE_DONE: return documents
            default: throw KnowledgeStoreError.executionFailed(errorMessage(db))
            }
        }
    }

    public func replaceDocument(_ document: KnowledgeDocument, chunks: [KnowledgeChunk]) async throws {
        try validate(document: document, chunks: chunks)
        let metadataJSON = try encodeMetadata(document.metadata)
        let db = connection.raw
        try Self.execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            var cleanup: OpaquePointer?
            try prepare(db, sql: "DELETE FROM knowledge_documents WHERE source_resource_id = ?1 AND id <> ?2;", statement: &cleanup)
            bind(document.sourceResourceID.rawValue, to: cleanup, index: 1)
            bind(document.id.uuidString, to: cleanup, index: 2)
            try stepDone(cleanup, db: db)
            sqlite3_finalize(cleanup)

            var documentStatement: OpaquePointer?
            try prepare(db, sql: "INSERT INTO knowledge_documents (id, source_resource_id, display_name, media_type, page_count, metadata_json, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT(id) DO UPDATE SET source_resource_id=excluded.source_resource_id, display_name=excluded.display_name, media_type=excluded.media_type, page_count=excluded.page_count, metadata_json=excluded.metadata_json, updated_at=excluded.updated_at;", statement: &documentStatement)
            bind(document.id.uuidString, to: documentStatement, index: 1)
            bind(document.sourceResourceID.rawValue, to: documentStatement, index: 2)
            bind(document.displayName, to: documentStatement, index: 3)
            bind(document.mediaType, to: documentStatement, index: 4)
            sqlite3_bind_int64(documentStatement, 5, sqlite3_int64(document.pageCount))
            bind(metadataJSON, to: documentStatement, index: 6)
            sqlite3_bind_double(documentStatement, 7, document.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(documentStatement, 8, document.updatedAt.timeIntervalSince1970)
            try stepDone(documentStatement, db: db)
            sqlite3_finalize(documentStatement)

            var deleteChunks: OpaquePointer?
            try prepare(db, sql: "DELETE FROM knowledge_chunks WHERE document_id = ?1;", statement: &deleteChunks)
            bind(document.id.uuidString, to: deleteChunks, index: 1)
            try stepDone(deleteChunks, db: db)
            sqlite3_finalize(deleteChunks)

            let insertSQL = "INSERT INTO knowledge_chunks (id, document_id, ordinal, page_start, page_end, text) VALUES (?1, ?2, ?3, ?4, ?5, ?6);"
            for chunk in chunks {
                var statement: OpaquePointer?
                try prepare(db, sql: insertSQL, statement: &statement)
                bind(chunk.id.uuidString, to: statement, index: 1)
                bind(chunk.documentID.uuidString, to: statement, index: 2)
                sqlite3_bind_int64(statement, 3, sqlite3_int64(chunk.ordinal))
                sqlite3_bind_int64(statement, 4, sqlite3_int64(chunk.pageStart))
                sqlite3_bind_int64(statement, 5, sqlite3_int64(chunk.pageEnd))
                bind(chunk.text, to: statement, index: 6)
                try stepDone(statement, db: db)
                sqlite3_finalize(statement)
            }
            try Self.execute(db, sql: "COMMIT;")
        } catch {
            try? Self.execute(db, sql: "ROLLBACK;")
            throw error
        }
    }

    private func validate(document: KnowledgeDocument, chunks: [KnowledgeChunk]) throws {
        guard document.pageCount > 0 else { throw KnowledgeStoreError.invalidRecord("pageCount must be positive") }
        guard !document.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KnowledgeStoreError.invalidRecord("displayName cannot be empty") }
        guard !document.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KnowledgeStoreError.invalidRecord("mediaType cannot be empty") }
        guard !chunks.isEmpty else { throw KnowledgeStoreError.invalidRecord("at least one chunk is required") }
        for (expectedOrdinal, chunk) in chunks.enumerated() {
            guard chunk.documentID == document.id else { throw KnowledgeStoreError.invalidRecord("chunk document identity mismatch") }
            guard chunk.ordinal == expectedOrdinal else { throw KnowledgeStoreError.invalidRecord("chunk ordinals must be contiguous from zero") }
            guard chunk.pageStart > 0, chunk.pageEnd >= chunk.pageStart, chunk.pageEnd <= document.pageCount else { throw KnowledgeStoreError.invalidRecord("chunk page provenance is outside the document") }
            guard !chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KnowledgeStoreError.invalidRecord("chunk text cannot be empty") }
        }
    }

    private func decodeDocument(_ statement: OpaquePointer?) throws -> KnowledgeDocument {
        guard let id = UUID(uuidString: text(statement, column: 0)) else { throw KnowledgeStoreError.corruptData("invalid document UUID") }
        let metadataText = text(statement, column: 5)
        guard let metadataData = metadataText.data(using: .utf8) else { throw KnowledgeStoreError.corruptData("metadata is not UTF-8") }
        let metadata: [String: JSONValue]
        do { metadata = try JSONDecoder().decode([String: JSONValue].self, from: metadataData) }
        catch { throw KnowledgeStoreError.corruptData("invalid metadata JSON") }
        return KnowledgeDocument(
            id: id,
            sourceResourceID: UserFileResourceID(rawValue: text(statement, column: 1)),
            displayName: text(statement, column: 2),
            mediaType: text(statement, column: 3),
            pageCount: Int(sqlite3_column_int64(statement, 4)),
            metadata: metadata,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        )
    }

    private func encodeMetadata(_ metadata: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        guard let string = String(data: data, encoding: .utf8) else { throw KnowledgeStoreError.invalidRecord("metadata could not be encoded as UTF-8") }
        return string
    }

    private func prepare(_ db: OpaquePointer, sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw KnowledgeStoreError.statementFailed(errorMessage(db)) }
    }
    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }
    private func stepDone(_ statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw KnowledgeStoreError.executionFailed(errorMessage(db)) }
    }
    private func text(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }
    private func errorMessage(_ db: OpaquePointer) -> String { String(cString: sqlite3_errmsg(db)) }
    private static func execute(_ db: OpaquePointer, sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorPointer { sqlite3_free(errorPointer) }
            throw KnowledgeStoreError.executionFailed(message)
        }
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS knowledge_documents (
        id TEXT PRIMARY KEY,
        source_resource_id TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        media_type TEXT NOT NULL,
        page_count INTEGER NOT NULL CHECK(page_count > 0),
        metadata_json TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS knowledge_chunks (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
        page_start INTEGER NOT NULL CHECK(page_start > 0),
        page_end INTEGER NOT NULL CHECK(page_end >= page_start),
        text TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES knowledge_documents(id) ON DELETE CASCADE,
        UNIQUE(document_id, ordinal)
    );
    CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_document ON knowledge_chunks(document_id, ordinal);
    """
}
