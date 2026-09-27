import XCTest
import CSQLite
@testable import IlumCore

final class IncrementalConversationTests: XCTestCase {
    func testLongChatAppendAndReopenDoNotRewriteUnchangedRows() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        var chat = Conversation(messages: (0..<1000).map {
            ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "message \($0)")
        })
        try await store.saveConversation(chat)
        try audit(url)
        chat.messages.append(ChatMessage(role: .user, content: "new question"))
        try await store.saveConversation(chat)
        XCTAssertEqual(try count(url, "I"), 1)
        XCTAssertEqual(try count(url, "U"), 0)
        XCTAssertEqual(try count(url, "D"), 0)
        let reopened = try SQLiteConversationStore(url: url)
        let snapshot = try await reopened.loadConversation(id: chat.id)
        let loaded = try XCTUnwrap(snapshot)
        XCTAssertEqual(loaded.messages.map(\.id), chat.messages.map(\.id))
        try await reopened.saveConversation(loaded)
        XCTAssertEqual(try count(url, "I"), 1)
        XCTAssertEqual(try count(url, "U"), 0)
        XCTAssertEqual(try count(url, "D"), 0)
    }

    func testEditsReorderRemovalAndEmptySnapshotSurviveReopen() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let a = ChatMessage(role: .user, content: "a", createdAt: Date(timeIntervalSince1970: 10))
        let b = ChatMessage(role: .assistant, content: "b", createdAt: Date(timeIntervalSince1970: 11))
        let c = ChatMessage(role: .user, content: "c", createdAt: Date(timeIntervalSince1970: 12))
        var chat = Conversation(messages: [a, b, c])
        try await store.saveConversation(chat)
        chat.messages = [c, ChatMessage(id: a.id, role: .assistant, content: "edited", createdAt: a.createdAt)]
        chat.title = "Renamed"
        try await store.saveConversation(chat)
        let reopened = try SQLiteConversationStore(url: url)
        let loaded = try await reopened.loadConversation(id: chat.id)
        XCTAssertEqual(loaded?.messages, chat.messages)
        XCTAssertEqual(loaded?.title, "Renamed")
        chat.messages = []
        try await reopened.saveConversation(chat)
        let empty = try await store.loadConversation(id: chat.id)
        XCTAssertEqual(empty?.messages, [])
    }

    func testForeignMessageIDRollsBackAllChanges() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let other = Conversation(messages: [ChatMessage(role: .user, content: "other chat")])
        let original = Conversation(title: "Original", messages: [ChatMessage(role: .user, content: "keep")])
        try await store.saveConversation(other)
        try await store.saveConversation(original)
        var changed = original
        changed.title = "Must roll back"
        changed.messages = [ChatMessage(role: .user, content: "also roll back"), other.messages[0]]
        do {
            try await store.saveConversation(changed)
            XCTFail("Cross-conversation message identity must fail")
        } catch let error as SQLiteStoreError {
            guard case .corruptData = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let loaded = try await store.loadConversation(id: original.id)
        let untouched = try await store.loadConversation(id: other.id)
        XCTAssertEqual(loaded?.title, original.title)
        XCTAssertEqual(loaded?.messages.map(\.id), original.messages.map(\.id))
        XCTAssertEqual(untouched?.messages.map(\.content), ["other chat"])
    }

    func testDuplicateIDsDoNotDamageSavedHistory() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        var chat = Conversation(messages: [ChatMessage(role: .user, content: "keep")])
        try await store.saveConversation(chat)
        chat.messages.append(chat.messages[0])
        do {
            try await store.saveConversation(chat)
            XCTFail("Duplicate IDs must fail")
        } catch let error as SQLiteStoreError {
            guard case .corruptData = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let loaded = try await store.loadConversation(id: chat.id)
        XCTAssertEqual(loaded?.messages.count, 1)
    }

    func testCancelledModelLeavesOnlyDurableUserMessageAfterReopen() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let runtime = AgentRuntime(store: store, model: CancelledHistoryModel())
        let id = UUID()
        do {
            _ = try await runtime.send("keep this question", conversationID: id)
            XCTFail("Cancelled turn must not succeed")
        } catch is CancellationError { }
        let reopened = try SQLiteConversationStore(url: url)
        let loaded = try await reopened.loadConversation(id: id)
        XCTAssertEqual(loaded?.messages.map(\.role), [.user])
        XCTAssertEqual(loaded?.messages.map(\.content), ["keep this question"])
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ilum-delta-\(UUID())/chat.sqlite")
    }

    private func audit(_ url: URL) throws {
        try sql(url, """
        CREATE TABLE write_audit(operation TEXT);
        CREATE TRIGGER audit_insert AFTER INSERT ON messages BEGIN INSERT INTO write_audit VALUES ('I'); END;
        CREATE TRIGGER audit_update AFTER UPDATE ON messages BEGIN INSERT INTO write_audit VALUES ('U'); END;
        CREATE TRIGGER audit_delete AFTER DELETE ON messages BEGIN INSERT INTO write_audit VALUES ('D'); END;
        """)
    }

    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteStoreError.openFailed("test database") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func count(_ url: URL, _ operation: String) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteStoreError.openFailed("test database") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM write_audit WHERE operation = '\(operation)';", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statementFailed("test audit query")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SQLiteStoreError.executionFailed("test audit count") }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

private struct CancelledHistoryModel: ModelProvider {
    func respond(to request: ModelRequest) async throws -> ModelTurn { throw CancellationError() }
}
