import XCTest
@testable import IlumCore

final class ConversationCatalogTests: XCTestCase {
    func testConversationCatalogIsNewestFirstAndCountsMessages() async throws {
        let store = try SQLiteConversationStore(url: temporaryURL("catalog.sqlite3"))
        let older = Conversation(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            messages: [ChatMessage(role: .user, content: "one")]
        )
        let newer = Conversation(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            messages: [
                ChatMessage(role: .user, content: "one"),
                ChatMessage(role: .assistant, content: "two")
            ]
        )

        try await store.saveConversation(older)
        try await store.saveConversation(newer)

        let summaries = try await store.listConversations()
        XCTAssertEqual(summaries.map(\.id), [newer.id, older.id])
        XCTAssertEqual(summaries.first?.messageCount, 2)
        XCTAssertEqual(summaries.last?.messageCount, 1)
    }

    func testDeleteConversationCascadesMessagesAndRemovesCatalogEntry() async throws {
        let store = try SQLiteConversationStore(url: temporaryURL("delete.sqlite3"))
        let conversation = Conversation(
            title: "Delete me",
            messages: [ChatMessage(role: .user, content: "hello")]
        )
        try await store.saveConversation(conversation)

        try await store.deleteConversation(id: conversation.id)

        let loaded = try await store.loadConversation(id: conversation.id)
        let summaries = try await store.listConversations()
        XCTAssertNil(loaded)
        XCTAssertTrue(summaries.isEmpty)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-conversation-catalog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
