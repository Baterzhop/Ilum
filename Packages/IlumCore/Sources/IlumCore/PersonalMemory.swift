import Foundation
import CSQLite

public enum PersonalMemoryKind: String, Codable, CaseIterable, Sendable {
    case fact
    case preference
    case goal
    case routine
    case note
}

public struct PersonalMemoryRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: PersonalMemoryKind
    public let content: String
    public let tags: [String]
    public let importance: Double
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: PersonalMemoryKind,
        content: String,
        tags: [String] = [],
        importance: Double = 0.5,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.tags = tags
        self.importance = min(max(importance, 0), 1)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol PersonalMemoryStore: Sendable {
    func remember(
        content: String,
        kind: PersonalMemoryKind,
        tags: [String],
        importance: Double
    ) async throws -> PersonalMemoryRecord
    func forget(id: UUID) async throws
    func search(_ query: String, limit: Int) async throws -> [PersonalMemoryRecord]
    func list(limit: Int) async throws -> [PersonalMemoryRecord]
}

public enum PersonalMemoryError: Error, CustomStringConvertible, Sendable {
    case emptyContent
    case invalidLimit
    case openFailed(String)
    case statementFailed(String)
    case executionFailed(String)
    case corruptData(String)

    public var description: String {
        switch self {
        case .emptyContent: return "Personal memory content cannot be empty."
        case .invalidLimit: return "Personal memory limit must be between 1 and 100."
        case .openFailed(let detail): return "Personal memory database could not be opened: \(detail)"
        case .statementFailed(let detail): return "Personal memory statement failed: \(detail)"
        case .executionFailed(let detail): return "Personal memory operation failed: \(detail)"
        case .corruptData(let detail): return "Personal memory data is invalid: \(detail)"
        }
    }
}

private final class PersonalMemorySQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
    init(raw: OpaquePointer) { self.raw = raw }
    deinit { sqlite3_close_v2(raw) }
}

public actor SQLitePersonalMemoryStore: PersonalMemoryStore {
    private let connection: PersonalMemorySQLiteConnection

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var raw: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &raw, flags, nil)
        guard status == SQLITE_OK, let raw else {
            let message = raw.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite status \(status)"
            if let raw { sqlite3_close_v2(raw) }
            throw PersonalMemoryError.openFailed(message)
        }

        do {
            try Self.execute(raw, sql: "PRAGMA journal_mode = WAL;")
            try Self.execute(raw, sql: "PRAGMA synchronous = NORMAL;")
            try Self.execute(raw, sql: Self.schema)
            connection = PersonalMemorySQLiteConnection(raw: raw)
        } catch {
            sqlite3_close_v2(raw)
            throw error
        }
    }

    public func remember(
        content: String,
        kind: PersonalMemoryKind,
        tags: [String] = [],
        importance: Double = 0.5
    ) async throws -> PersonalMemoryRecord {
        let normalized = Self.normalizedContent(content)
        guard !normalized.isEmpty else { throw PersonalMemoryError.emptyContent }
        let now = Date()
        let safeImportance = min(max(importance, 0), 1)
        let cleanTags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()

        if let existing = try find(canonicalText: normalized) {
            let updated = PersonalMemoryRecord(
                id: existing.id,
                kind: kind,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: cleanTags,
                importance: safeImportance,
                createdAt: existing.createdAt,
                updatedAt: now
            )
            try write(updated, canonicalText: normalized)
            return updated
        }

        let record = PersonalMemoryRecord(
            kind: kind,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: cleanTags,
            importance: safeImportance,
            createdAt: now,
            updatedAt: now
        )
        try write(record, canonicalText: normalized)
        return record
    }

    public func forget(id: UUID) async throws {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(db, sql: "DELETE FROM personal_memories WHERE id = ?1;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersonalMemoryError.executionFailed(errorMessage(db))
        }
    }

    public func search(_ query: String, limit: Int = 8) async throws -> [PersonalMemoryRecord] {
        guard (1...100).contains(limit) else { throw PersonalMemoryError.invalidLimit }
        let records = try loadAll(limit: 500)
        let queryTerms = Set(LexicalKnowledgeRetriever.tokenize(query))

        if queryTerms.isEmpty {
            return Array(records.sorted(by: Self.defaultOrder).prefix(limit))
        }

        let scored = records.compactMap { record -> (PersonalMemoryRecord, Double)? in
            let searchable = ([record.kind.rawValue, record.content] + record.tags).joined(separator: " ")
            let memoryTerms = Set(LexicalKnowledgeRetriever.tokenize(searchable))
            let matched = queryTerms.intersection(memoryTerms).count
            guard matched > 0 else { return nil }
            let coverage = Double(matched) / Double(queryTerms.count)
            let score = coverage + (record.importance * 0.20)
            return (record, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.importance != rhs.0.importance { return lhs.0.importance > rhs.0.importance }
                if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .prefix(limit)
            .map(\.0)
    }

    public func list(limit: Int = 50) async throws -> [PersonalMemoryRecord] {
        guard (1...100).contains(limit) else { throw PersonalMemoryError.invalidLimit }
        return Array(try loadAll(limit: limit).sorted(by: Self.defaultOrder).prefix(limit))
    }

    private static func defaultOrder(_ lhs: PersonalMemoryRecord, _ rhs: PersonalMemoryRecord) -> Bool {
        if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func normalizedContent(_ content: String) -> String {
        content
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private func find(canonicalText: String) throws -> PersonalMemoryRecord? {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(
            db,
            sql: "SELECT id, kind, content, tags_json, importance, created_at, updated_at FROM personal_memories WHERE canonical_text = ?1 LIMIT 1;",
            statement: &statement
        )
        defer { sqlite3_finalize(statement) }
        bind(canonicalText, to: statement, index: 1)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return try decode(statement)
        case SQLITE_DONE: return nil
        default: throw PersonalMemoryError.executionFailed(errorMessage(db))
        }
    }

    private func write(_ record: PersonalMemoryRecord, canonicalText: String) throws {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(
            db,
            sql: """
            INSERT INTO personal_memories(id, canonical_text, kind, content, tags_json, importance, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(canonical_text) DO UPDATE SET
                kind = excluded.kind,
                content = excluded.content,
                tags_json = excluded.tags_json,
                importance = excluded.importance,
                updated_at = excluded.updated_at;
            """,
            statement: &statement
        )
        defer { sqlite3_finalize(statement) }
        bind(record.id.uuidString, to: statement, index: 1)
        bind(canonicalText, to: statement, index: 2)
        bind(record.kind.rawValue, to: statement, index: 3)
        bind(record.content, to: statement, index: 4)
        bind(try encodeTags(record.tags), to: statement, index: 5)
        sqlite3_bind_double(statement, 6, record.importance)
        sqlite3_bind_double(statement, 7, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 8, record.updatedAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersonalMemoryError.executionFailed(errorMessage(db))
        }
    }

    private func loadAll(limit: Int) throws -> [PersonalMemoryRecord] {
        let db = connection.raw
        var statement: OpaquePointer?
        try prepare(
            db,
            sql: "SELECT id, kind, content, tags_json, importance, created_at, updated_at FROM personal_memories ORDER BY updated_at DESC LIMIT ?1;",
            statement: &statement
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(limit))

        var output: [PersonalMemoryRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: output.append(try decode(statement))
            case SQLITE_DONE: return output
            default: throw PersonalMemoryError.executionFailed(errorMessage(db))
            }
        }
    }

    private func decode(_ statement: OpaquePointer?) throws -> PersonalMemoryRecord {
        guard
            let id = UUID(uuidString: text(statement, column: 0)),
            let kind = PersonalMemoryKind(rawValue: text(statement, column: 1))
        else { throw PersonalMemoryError.corruptData("invalid id or kind") }

        let tagsText = text(statement, column: 3)
        guard let data = tagsText.data(using: .utf8), let tags = try? JSONDecoder().decode([String].self, from: data) else {
            throw PersonalMemoryError.corruptData("invalid tags JSON")
        }

        return PersonalMemoryRecord(
            id: id,
            kind: kind,
            content: text(statement, column: 2),
            tags: tags,
            importance: sqlite3_column_double(statement, 4),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        )
    }

    private func encodeTags(_ tags: [String]) throws -> String {
        let data = try JSONEncoder().encode(tags)
        guard let result = String(data: data, encoding: .utf8) else {
            throw PersonalMemoryError.corruptData("could not encode tags")
        }
        return result
    }

    private func prepare(_ db: OpaquePointer, sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersonalMemoryError.statementFailed(errorMessage(db))
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func text(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func errorMessage(_ db: OpaquePointer) -> String { String(cString: sqlite3_errmsg(db)) }

    private static func execute(_ db: OpaquePointer, sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let detail = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorPointer { sqlite3_free(errorPointer) }
            throw PersonalMemoryError.executionFailed(detail)
        }
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS personal_memories (
        id TEXT PRIMARY KEY,
        canonical_text TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        importance REAL NOT NULL CHECK(importance >= 0 AND importance <= 1),
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_personal_memories_updated
        ON personal_memories(updated_at DESC);
    """
}

public struct MemorySearchInput: Codable, Equatable, Sendable {
    public let query: String
    public let limit: Int?
    public init(query: String, limit: Int? = nil) { self.query = query; self.limit = limit }
}

public struct MemorySearchOutput: Codable, Equatable, Sendable {
    public let memories: [PersonalMemoryRecord]
    public init(memories: [PersonalMemoryRecord]) { self.memories = memories }
}

public struct MemorySearchTool: Tool {
    public static let descriptor = ToolDescriptor(
        name: "memory.search",
        version: "1",
        summary: "Search Ilum's local personal memory for relevant user facts, preferences, goals, routines, or notes.",
        risk: .readOnly,
        capability: .readAppData,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(20)])
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false)
        ])
    )

    private let store: any PersonalMemoryStore
    public init(store: any PersonalMemoryStore) { self.store = store }
    public func resource(for input: MemorySearchInput) throws -> ResourceScope { .appData("personal-memory") }
    public func execute(_ input: MemorySearchInput) async throws -> MemorySearchOutput {
        MemorySearchOutput(memories: try await store.search(input.query, limit: min(max(input.limit ?? 8, 1), 20)))
    }
}

public struct MemoryRememberInput: Codable, Equatable, Sendable {
    public let content: String
    public let kind: PersonalMemoryKind?
    public let tags: [String]?
    public let importance: Double?
    public init(content: String, kind: PersonalMemoryKind? = nil, tags: [String]? = nil, importance: Double? = nil) {
        self.content = content; self.kind = kind; self.tags = tags; self.importance = importance
    }
}

public struct MemoryRememberOutput: Codable, Equatable, Sendable {
    public let memory: PersonalMemoryRecord
    public init(memory: PersonalMemoryRecord) { self.memory = memory }
}

public struct MemoryRememberTool: Tool {
    public static let descriptor = ToolDescriptor(
        name: "memory.remember",
        version: "1",
        summary: "Persist one stable user fact, preference, goal, routine, or note in Ilum's local personal memory.",
        risk: .internalWrite,
        capability: .writeAppData,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "content": .object(["type": .string("string")]),
                "kind": .object(["type": .string("string"), "enum": .array(PersonalMemoryKind.allCases.map { .string($0.rawValue) })]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "importance": .object(["type": .string("number"), "minimum": .number(0), "maximum": .number(1)])
            ]),
            "required": .array([.string("content")]),
            "additionalProperties": .bool(false)
        ])
    )

    private let store: any PersonalMemoryStore
    public init(store: any PersonalMemoryStore) { self.store = store }
    public func resource(for input: MemoryRememberInput) throws -> ResourceScope { .appData("personal-memory") }
    public func permissionRequest(for input: MemoryRememberInput) throws -> PermissionRequest {
        PermissionRequest(
            capability: Self.descriptor.capability,
            resource: .appData("personal-memory"),
            reason: "Save this information to Ilum's durable personal memory: \(input.content)",
            resourceDisplayName: "Personal Memory"
        )
    }
    public func execute(_ input: MemoryRememberInput) async throws -> MemoryRememberOutput {
        let record = try await store.remember(
            content: input.content,
            kind: input.kind ?? .fact,
            tags: input.tags ?? [],
            importance: input.importance ?? 0.5
        )
        return MemoryRememberOutput(memory: record)
    }
}

public struct MemoryForgetInput: Codable, Equatable, Sendable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}

public struct MemoryForgetOutput: Codable, Equatable, Sendable {
    public let forgottenID: UUID
    public init(forgottenID: UUID) { self.forgottenID = forgottenID }
}

public struct MemoryForgetTool: Tool {
    public static let descriptor = ToolDescriptor(
        name: "memory.forget",
        version: "1",
        summary: "Delete one explicitly identified item from Ilum's durable personal memory.",
        risk: .internalWrite,
        capability: .writeAppData,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string"), "description": .string("UUID returned by memory.search")])
            ]),
            "required": .array([.string("id")]),
            "additionalProperties": .bool(false)
        ])
    )

    private let store: any PersonalMemoryStore
    public init(store: any PersonalMemoryStore) { self.store = store }
    public func resource(for input: MemoryForgetInput) throws -> ResourceScope { .appData("personal-memory") }
    public func permissionRequest(for input: MemoryForgetInput) throws -> PermissionRequest {
        PermissionRequest(
            capability: Self.descriptor.capability,
            resource: .appData("personal-memory"),
            reason: "Delete personal memory item \(input.id.uuidString).",
            resourceDisplayName: "Personal Memory"
        )
    }
    public func execute(_ input: MemoryForgetInput) async throws -> MemoryForgetOutput {
        try await store.forget(id: input.id)
        return MemoryForgetOutput(forgottenID: input.id)
    }
}
