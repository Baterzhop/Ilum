import Foundation
import XCTest
@testable import IlumCore

final class AgentCancellationTests: XCTestCase {
    func testCancellationKeepsDurableUserTurnButDoesNotPersistAssistantReply() async throws {
        let store = CancellationConversationStore()
        let runtime = AgentRuntime(
            store: store,
            model: SlowCancellableModel()
        )
        let conversationID = UUID()

        let task = Task {
            try await runtime.send(
                "This user turn must survive cancellation.",
                conversationID: conversationID
            )
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled model turn must not complete normally")
        } catch is CancellationError {
            // Expected.
        }

        let persisted = try await store.loadConversation(id: conversationID)
        XCTAssertEqual(persisted?.messages.map(\.role), [.user])
        XCTAssertEqual(
            persisted?.messages.first?.content,
            "This user turn must survive cancellation."
        )
    }
}

private actor CancellationConversationStore: ConversationStore {
    private var conversations: [UUID: Conversation] = [:]

    func loadConversation(id: UUID) async throws -> Conversation? {
        conversations[id]
    }

    func saveConversation(_ conversation: Conversation) async throws {
        conversations[conversation.id] = conversation
    }
}

private struct SlowCancellableModel: ModelProvider, Sendable {
    func respond(to request: ModelRequest) async throws -> ModelTurn {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return .final("This reply must never be persisted after cancellation.")
    }
}
