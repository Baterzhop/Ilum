import Foundation
import CSQLite

public enum SQLiteStoreError: Error, CustomStringConvertible, Sendable {
    case openFailed(String)
    case statementFailed(String)
    case executionFailed(String)
    case corruptData(String)
    case pendingExecutionNotFound(UUID)

    public var description: String {
        switch self {
        case .openFailed(let message): return "SQLite open failed: \(message)"
        case .statementFailed(let message): return "SQLite statement failed: \(message)"
        case .executionFailed(let message): return "SQLite execution failed: \(message)"
        case .corruptData(let message): return "SQLite data is invalid: \(message)"
        case .pendingExecutionNotFound(let id): return "Pending execution \(id.uuidString) no longer exists."
        }
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
    init(raw: OpaquePointer) { self.raw = raw }
    deinit { sqlite3_close_v2(raw) }
}

public actor SQLiteConversationStore: ConversationStore, PendingExecutionStore {
    private let connection: SQLiteConnection

    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rawHandle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &rawHandle, flags, nil)
        guard result == SQLITE_OK, let rawHandle else {
            let message = rawHandle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            if let rawHandle { sqlite3_close_v2(rawHandle) }
            throw SQLiteStoreError.openFailed(message)
        }
        do {
            try Self.execute(rawHandle, sql: "PRAGMA foreign_keys = ON;")
            try Self.execute(rawHandle, sql: "PRAGMA journal_mode = WAL;")
            try Self.execute(rawHandle, sql: "PRAGMA synchronous = NORMAL;")
            try Self.applyMigrations(rawHandle)
            self.connection = SQLiteConnection(raw: rawHandle)
        } catch {
            sqlite3_close_v2(rawHandle)
            throw error
        }
    }

    public func loadConversation(id: UUID) async throws -> Conversation? {
        let db = connection.raw
        var conversationStatement: OpaquePointer?
        try prepare(db, sql: "SELECT title, created_at, updated_at FROM conversations WHERE id = ?1 LIMIT 1;", statement: &conversationStatement)
        defer { sqlite3_finalize(conversationStatement) }
        bind(id.uuidString, to: conversationStatement, index: 1)

        switch sqlite3_step(conversationStatement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return nil
        default:
            throw SQLiteStoreError.executionFailed(errorMessage(db))
        }

        let title = text(conversationStatement, column: 0)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(conversationStatement, 1))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(conversationStatement, 2))

        var messageStatement: OpaquePointer?
        try prepare(db, sql: "SELECT id, role, content, created_at FROM messages WHERE conversation_id = ?1 ORDER BY sequence_number ASC;", statement: &messageStatement)
        defer { sqlite3_finalize(messageStatement) }
        bind(id.uuidString, to: messageStatement, index: 1)

        var messages: [ChatMessage] = []
        while true {
            switch sqlite3_step(messageStatement) {
            case SQLITE_ROW:
                guard let messageID = UUID(uuidString: text(messageStatement, column: 0)),
                      let role = ChatRole(rawValue: text(messageStatement, column: 1)) else {
                    throw SQLiteStoreError.corruptData("invalid message identity or role")
                }
                messages.append(ChatMessage(
                    id: messageID,
                    role: role,
                    content: text(messageStatement, column: 2),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(messageStatement, 3))
                ))
            case SQLITE_DONE:
                return Conversation(
                    id: id,
                    title: title,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    messages: messages
                )
            default:
                throw SQLiteStoreError.executionFailed(errorMessage(db))
            }
        }
    }

    public func saveConversation(_ conversation: Conversation) async throws {
        let db = connection.raw
        try Self.execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertConversation(conversation, db: db)
            try replaceMessages(conversation, db: db)
            try Self.execute(db, sql: "COMMIT;")
        } catch {
            try? Self.execute(db, sql: "ROLLBACK;")
            throw error
        }
    }

    public func listConversations(limit: Int = 100) async throws -> [ConversationSummary] {
        let db = connection.raw
        let boundedLimit = min(max(limit, 1), 500)
        let sql = """
        SELECT c.id, c.title, c.created_at, c.updated_at, COUNT(m.id)
        FROM conversations c
        LEFT JOIN messages m ON m.conversation_id = c.id
        GROUP BY c.id, c.title, c.created_at, c.updated_at
        ORDER BY c.updated_at DESC, c.id ASC
        LIMIT ?1;
        """

        var statement: OpaquePointer?
        try prepare(db, sql: sql, statement: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(boundedLimit))

        var summaries: [ConversationSummary] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = UUID(uuidString: text(statement, column: 0)) else {
                    throw SQLiteStoreError.corruptData("invalid conversation UUID in catalog")
                }
                summaries.append(ConversationSummary(
                    id: id,
                    title: text(statement, column: 1),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    messageCount: Int(sqlite3_column_int64(statement, 4))
                ))
            case SQLITE_DONE:
                return summaries
            default:
                throw SQLiteStoreError.executionFailed(errorMessage(db))
            }
        }
    }

    public func deleteConversation(id: UUID) async throws {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(db, sql: "DELETE FROM conversations WHERE id = ?1;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, index: 1)
        try stepDone(statement, db: db)
    }

    public func savePendingExecution(_ snapshot: PendingExecutionSnapshot) async throws {
        guard snapshot.formatVersion == PendingExecutionSnapshot.currentFormatVersion else {
            throw SQLiteStoreError.corruptData("unsupported pending execution format \(snapshot.formatVersion)")
        }
        guard snapshot.conversationID == snapshot.conversation.id else {
            throw SQLiteStoreError.corruptData("pending execution conversation identity mismatch")
        }
        let encoded = try JSONEncoder().encode(snapshot)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw SQLiteStoreError.corruptData("pending execution could not be encoded as UTF-8 JSON")
        }

        let db = connection.raw
        let sql = """
        INSERT INTO pending_executions(id, conversation_id, payload_version, payload_json, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(conversation_id) DO UPDATE SET
            id = excluded.id,
            payload_version = excluded.payload_version,
            payload_json = excluded.payload_json,
            created_at = excluded.created_at;
        """
        var statement: OpaquePointer?
        try prepare(db, sql: sql, statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(snapshot.id.uuidString, to: statement, index: 1)
        bind(snapshot.conversationID.uuidString, to: statement, index: 2)
        sqlite3_bind_int(statement, 3, Int32(snapshot.formatVersion))
        bind(payload, to: statement, index: 4)
        sqlite3_bind_double(statement, 5, snapshot.createdAt.timeIntervalSince1970)
        try stepDone(statement, db: db)
    }

    public func loadPendingExecution(conversationID: UUID) async throws -> PendingExecutionSnapshot? {
        try loadPendingExecution(whereSQL: "conversation_id = ?1", value: conversationID.uuidString)
    }

    public func loadPendingExecution(id: UUID) async throws -> PendingExecutionSnapshot? {
        try loadPendingExecution(whereSQL: "id = ?1", value: id.uuidString)
    }

    public func resolvePendingExecution(id: UUID, conversation: Conversation) async throws {
        let db = connection.raw
        try Self.execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertConversation(conversation, db: db)
            try replaceMessages(conversation, db: db)

            var statement: OpaquePointer?
            try prepare(
                db,
                sql: "DELETE FROM pending_executions WHERE id = ?1 AND conversation_id = ?2;",
                statement: &statement
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: statement, index: 1)
            bind(conversation.id.uuidString, to: statement, index: 2)
            try stepDone(statement, db: db)
            guard sqlite3_changes(db) == 1 else {
                throw SQLiteStoreError.pendingExecutionNotFound(id)
            }

            try Self.execute(db, sql: "COMMIT;")
        } catch {
            try? Self.execute(db, sql: "ROLLBACK;")
            throw error
        }
    }

    private func loadPendingExecution(whereSQL: String, value: String) throws -> PendingExecutionSnapshot? {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(
            db,
            sql: "SELECT payload_version, payload_json FROM pending_executions WHERE \(whereSQL) LIMIT 1;",
            statement: &statement
        )
        defer { sqlite3_finalize(statement) }
        bind(value, to: statement, index: 1)

        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            let version = Int(sqlite3_column_int(statement, 0))
            guard version == PendingExecutionSnapshot.currentFormatVersion else {
                throw SQLiteStoreError.corruptData("unsupported pending execution format \(version)")
            }
            let payload = text(statement, column: 1)
            guard let data = payload.data(using: .utf8) else {
                throw SQLiteStoreError.corruptData("pending execution payload is not UTF-8")
            }
            let snapshot: PendingExecutionSnapshot
            do {
                snapshot = try JSONDecoder().decode(PendingExecutionSnapshot.self, from: data)
            } catch {
                throw SQLiteStoreError.corruptData("pending execution JSON decode failed: \(error)")
            }
            guard snapshot.formatVersion == version,
                  snapshot.conversationID == snapshot.conversation.id else {
                throw SQLiteStoreError.corruptData("pending execution payload identity/version mismatch")
            }
            return snapshot
        default:
            throw SQLiteStoreError.executionFailed(errorMessage(db))
        }
    }

    private func upsertConversation(_ conversation: Conversation, db: OpaquePointer) throws {
        let sql = "INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT(id) DO UPDATE SET title = excluded.title, updated_at = excluded.updated_at;"
        var statement: OpaquePointer?
        try prepare(db, sql: sql, statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(conversation.id.uuidString, to: statement, index: 1)
        bind(conversation.title, to: statement, index: 2)
        sqlite3_bind_double(statement, 3, conversation.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, conversation.updatedAt.timeIntervalSince1970)
        try stepDone(statement, db: db)
    }

    private func replaceMessages(_ conversation: Conversation, db: OpaquePointer) throws {
        var deleteStatement: OpaquePointer?
        try prepare(db, sql: "DELETE FROM messages WHERE conversation_id = ?1;", statement: &deleteStatement)
        bind(conversation.id.uuidString, to: deleteStatement, index: 1)
        try stepDone(deleteStatement, db: db)
        sqlite3_finalize(deleteStatement)

        let sql = "INSERT INTO messages (id, conversation_id, role, content, created_at, sequence_number) VALUES (?1, ?2, ?3, ?4, ?5, ?6);"
        for (index, message) in conversation.messages.enumerated() {
            var statement: OpaquePointer?
            try prepare(db, sql: sql, statement: &statement)
            bind(message.id.uuidString, to: statement, index: 1)
            bind(conversation.id.uuidString, to: statement, index: 2)
            bind(message.role.rawValue, to: statement, index: 3)
            bind(message.content, to: statement, index: 4)
            sqlite3_bind_double(statement, 5, message.createdAt.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 6, sqlite3_int64(index))
            do {
                try stepDone(statement, db: db)
                sqlite3_finalize(statement)
            } catch {
                sqlite3_finalize(statement)
                throw error
            }
        }
    }

    private func prepare(_ db: OpaquePointer, sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statementFailed(errorMessage(db))
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func stepDone(_ statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.executionFailed(errorMessage(db))
        }
    }

    private func text(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    private func errorMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private static func applyMigrations(_ db: OpaquePointer) throws {
        try execute(
            db,
            sql: "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);"
        )
        var applied = try appliedMigrationVersions(db)
        for migration in migrations where !applied.contains(migration.version) {
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
            do {
                try execute(db, sql: migration.sql)
                try execute(
                    db,
                    sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (\(migration.version), CAST(strftime('%s','now') AS REAL));"
                )
                try execute(db, sql: "COMMIT;")
                applied.insert(migration.version)
            } catch {
                try? execute(db, sql: "ROLLBACK;")
                throw error
            }
        }
    }

    private static func appliedMigrationVersions(_ db: OpaquePointer) throws -> Set<Int> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT version FROM schema_migrations ORDER BY version ASC;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var versions: Set<Int> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                versions.insert(Int(sqlite3_column_int(statement, 0)))
            case SQLITE_DONE:
                return versions
            default:
                throw SQLiteStoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private static func execute(_ db: OpaquePointer, sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorPointer { sqlite3_free(errorPointer) }
            throw SQLiteStoreError.executionFailed(message)
        }
    }

    private static let migrations: [(version: Int, sql: String)] = [
        (
            version: 1,
            sql: """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                sequence_number INTEGER NOT NULL,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_messages_conversation_sequence ON messages(conversation_id, sequence_number);
            """
        ),
        (
            version: 2,
            sql: """
            CREATE TABLE IF NOT EXISTS pending_executions (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL UNIQUE,
                payload_version INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_pending_executions_conversation ON pending_executions(conversation_id);
            """
        )
    ]
}
