import Foundation
import CSQLite

private final class VectorSQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
    init(raw: OpaquePointer) { self.raw = raw }
    deinit { sqlite3_close_v2(raw) }
}

public actor SQLiteVectorIndex: DenseVectorIndex {
    public let databaseURL: URL
    private var connection: VectorSQLiteConnection?

    public init(databaseURL: URL) { self.databaseURL = databaseURL }

    public func replace(documentID: UUID, records: [DenseVectorRecord]) async throws {
        let db = try openIfNeeded()
        try exec("BEGIN IMMEDIATE;", db: db, migration: false)
        do {
            try deleteDocument(documentID, db: db)
            for record in records {
                guard record.document.id == documentID, record.chunk.documentID == documentID else {
                    throw VectorIndexError.writeFailed("Vector record document identity mismatch.")
                }
                try insert(record, db: db)
            }
            try exec("COMMIT;", db: db, migration: false)
        } catch {
            try? exec("ROLLBACK;", db: db, migration: false)
            throw error
        }
    }

    public func removeDocument(id: UUID) async throws {
        try deleteDocument(id, db: try openIfNeeded())
    }

    public func search(vector: [Float], modelID: String, limit: Int) async throws -> [KnowledgeHit] {
        try validate(vector)
        let db = try openIfNeeded()
        let statement = try prepare("SELECT chunk_id, document_id, source_resource_id, display_name, chunk_ordinal, page_start, page_end, text, vector FROM knowledge_vectors WHERE model_id = ?1 AND dimensions = ?2;", db: db)
        defer { sqlite3_finalize(statement) }
        try bind(modelID, index: 1, statement: statement, db: db)
        guard sqlite3_bind_int(statement, 2, Int32(vector.count)) == SQLITE_OK else { throw VectorIndexError.statementFailed(message(db)) }
        var scored: [(KnowledgeHit, Double)] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw VectorIndexError.statementFailed(message(db)) }
            guard let chunkIDString = text(statement, 0), let chunkID = UUID(uuidString: chunkIDString),
                  let documentIDString = text(statement, 1), let documentID = UUID(uuidString: documentIDString),
                  let source = text(statement, 2), let displayName = text(statement, 3),
                  let body = text(statement, 7), let storedVector = vectorData(statement, 8) else { continue }
            let similarity = try VectorMath.cosineSimilarity(vector, storedVector)
            scored.append((KnowledgeHit(
                documentID: documentID,
                sourceResourceID: UserFileResourceID(rawValue: source),
                displayName: displayName,
                chunkID: chunkID,
                chunkOrdinal: Int(sqlite3_column_int64(statement, 4)),
                pageStart: Int(sqlite3_column_int64(statement, 5)),
                pageEnd: Int(sqlite3_column_int64(statement, 6)),
                score: similarity,
                text: body
            ), similarity))
        }
        return scored.sorted {
            if $0.1 == $1.1 { return $0.0.chunkID.uuidString < $1.0.chunkID.uuidString }
            return $0.1 > $1.1
        }.prefix(max(0, limit)).map(\.0)
    }

    private func openIfNeeded() throws -> OpaquePointer {
        if let connection { return connection.raw }
        do { try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
        catch { throw VectorIndexError.openFailed(error.localizedDescription) }
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let handle else {
            let detail = handle.map(message) ?? "SQLite status \(status)"
            if let handle { sqlite3_close_v2(handle) }
            throw VectorIndexError.openFailed(detail)
        }
        do {
            try exec("PRAGMA journal_mode = WAL;", db: handle, migration: true)
            try migrate(handle)
        } catch { sqlite3_close_v2(handle); throw error }
        connection = VectorSQLiteConnection(raw: handle)
        return handle
    }

    private func migrate(_ db: OpaquePointer) throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS knowledge_vectors (
            chunk_id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            source_resource_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            chunk_ordinal INTEGER NOT NULL,
            page_start INTEGER NOT NULL,
            page_end INTEGER NOT NULL,
            model_id TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector BLOB NOT NULL,
            text TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_ilum_vectors_model_dimensions ON knowledge_vectors(model_id, dimensions);
        CREATE INDEX IF NOT EXISTS idx_ilum_vectors_document ON knowledge_vectors(document_id);
        """, db: db, migration: true)
    }

    private func insert(_ record: DenseVectorRecord, db: OpaquePointer) throws {
        try validate(record.vector)
        let statement = try prepare("INSERT OR REPLACE INTO knowledge_vectors(chunk_id, document_id, source_resource_id, display_name, chunk_ordinal, page_start, page_end, model_id, dimensions, vector, text, updated_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12);", db: db)
        defer { sqlite3_finalize(statement) }
        try bind(record.chunk.id.uuidString, index: 1, statement: statement, db: db)
        try bind(record.document.id.uuidString, index: 2, statement: statement, db: db)
        try bind(record.document.sourceResourceID.rawValue, index: 3, statement: statement, db: db)
        try bind(record.document.displayName, index: 4, statement: statement, db: db)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(record.chunk.ordinal))
        sqlite3_bind_int64(statement, 6, sqlite3_int64(record.chunk.pageStart))
        sqlite3_bind_int64(statement, 7, sqlite3_int64(record.chunk.pageEnd))
        try bind(record.modelID, index: 8, statement: statement, db: db)
        sqlite3_bind_int(statement, 9, Int32(record.vector.count))
        try bindVector(record.vector, index: 10, statement: statement, db: db)
        try bind(record.chunk.text, index: 11, statement: statement, db: db)
        sqlite3_bind_double(statement, 12, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw VectorIndexError.writeFailed(message(db)) }
    }

    private func deleteDocument(_ id: UUID, db: OpaquePointer) throws {
        let statement = try prepare("DELETE FROM knowledge_vectors WHERE document_id = ?1;", db: db)
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, index: 1, statement: statement, db: db)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw VectorIndexError.writeFailed(message(db)) }
    }

    private func validate(_ vector: [Float]) throws {
        guard !vector.isEmpty else { throw VectorIndexError.emptyVector }
        guard vector.allSatisfy({ $0.isFinite }) else { throw VectorIndexError.invalidVector }
    }
    private func encodeVector(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * 4)
        for value in vector {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
    private func decodeVector(_ data: Data) -> [Float]? {
        guard !data.isEmpty, data.count.isMultiple(of: 4) else { return nil }
        let bytes = [UInt8](data)
        var result: [Float] = []
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let bits = UInt32(bytes[offset]) | (UInt32(bytes[offset+1]) << 8) | (UInt32(bytes[offset+2]) << 16) | (UInt32(bytes[offset+3]) << 24)
            result.append(Float(bitPattern: bits))
        }
        return result
    }
    private func bindVector(_ vector: [Float], index: Int32, statement: OpaquePointer, db: OpaquePointer) throws {
        let data = encodeVector(vector)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
        guard status == SQLITE_OK else { throw VectorIndexError.writeFailed(message(db)) }
    }
    private func vectorData(_ statement: OpaquePointer, _ index: Int32) -> [Float]? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let raw = sqlite3_column_blob(statement, index) else { return nil }
        return decodeVector(Data(bytes: raw, count: count))
    }
    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw VectorIndexError.statementFailed(message(db)) }
        return statement
    }
    private func bind(_ value: String, index: Int32, statement: OpaquePointer, db: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, transient) }) == SQLITE_OK else { throw VectorIndexError.writeFailed(message(db)) }
    }
    private func exec(_ sql: String, db: OpaquePointer, migration: Bool) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            if migration { throw VectorIndexError.migrationFailed(message(db)) }
            throw VectorIndexError.writeFailed(message(db))
        }
    }
    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }
    private func message(_ db: OpaquePointer) -> String { String(cString: sqlite3_errmsg(db)) }
}
