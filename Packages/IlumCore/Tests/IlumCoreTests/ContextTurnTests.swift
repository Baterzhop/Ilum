import XCTest
@testable import IlumCore

final class ContextTurnTests: XCTestCase {
    // 1024 - 128 output - 64 safety = 832 units available for history.
    private let manager = ContextBudgetManager(
        policy: ContextBudgetPolicy(contextWindow: 1024, reservedOutputTokens: 128,
                                    safetyMarginTokens: 64, fixedSystemTokens: 0, perMessageOverheadTokens: 0),
        estimator: CharacterCostEstimator()
    )

    func testOldTurnIsDroppedWholeInsteadOfKeepingOrphanToolResult() {
        let messages = [message(.user, 500), message(.tool, 100), message(.assistant, 100), message(.user, 200)]
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertEqual(pack.messages.map(\.id), [messages[3].id])
        XCTAssertEqual(pack.report.droppedMessageCount, 3)
        XCTAssertTrue(pack.report.fits)
        XCTAssertEqual(messages.count, 4) // Packing never edits the durable conversation.
    }

    func testActiveRequestAndMultipleToolResultsStayTogetherOnOverflow() {
        let messages = [message(.user, 700), message(.tool, 100), message(.tool, 100)]
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertEqual(pack.messages, messages)
        XCTAssertFalse(pack.report.fits)
        XCTAssertEqual(pack.report.droppedMessageCount, 0)
    }

    func testSystemInstructionsStayPinnedWithNewestCompleteTurn() {
        let messages = [message(.system, 100), message(.user, 600), message(.assistant, 100), message(.user, 200)]
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertEqual(pack.messages, [messages[0], messages[3]])
        XCTAssertEqual(pack.report.historyTokens, 300)
        XCTAssertTrue(pack.report.fits)
    }

    func testExactBoundaryAndEmptyHistory() {
        let messages = [message(.user, 400), message(.assistant, 232), message(.user, 200)]
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertEqual(pack.messages, messages)
        XCTAssertEqual(pack.report.estimatedInputTokens, 832)
        XCTAssertTrue(pack.report.fits)
        let empty = manager.pack(messages: [], groundedContext: nil)
        XCTAssertTrue(empty.messages.isEmpty)
        XCTAssertTrue(empty.report.fits)
    }

    func testConsecutiveUserMessagesAfterCancelledTurns() {
        let messages = [message(.user, 700), message(.user, 200)]
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertEqual(pack.messages, [messages[1]])
        XCTAssertTrue(pack.report.fits)
    }

    func testRuntimeRejectsOversizedActiveTurnBeforeCallingModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ilum-overflow-\(UUID())/chat.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = CountingContextModel()
        let store = try SQLiteConversationStore(url: url)
        let chat = Conversation(messages: [message(.user, 800), message(.tool, 100)])
        try await store.saveConversation(chat)
        // Public send adds a new active user request. It too must be preserved,
        // and must fail before model invocation if that request cannot fit.
        let runtime = AgentRuntime(store: store, model: model, contextBudgetManager: manager)
        do {
            _ = try await runtime.send(String(repeating: "x", count: 900), conversationID: chat.id)
            XCTFail("Oversized active request must fail")
        } catch let error as AgentRuntimeError {
            guard case .contextBudgetExceeded = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let calls = await model.calls
        XCTAssertEqual(calls, 0)
        let loaded = try await store.loadConversation(id: chat.id)
        XCTAssertEqual(loaded?.messages.count, 3)
    }

    private func message(_ role: ChatRole, _ cost: Int) -> ChatMessage {
        ChatMessage(role: role, content: String(repeating: "x", count: cost))
    }
}

private struct CharacterCostEstimator: TokenEstimating {
    func estimateTokens(in text: String) -> Int { text.count }
}

private actor CountingContextModel: ModelProvider {
    private(set) var calls = 0
    func respond(to request: ModelRequest) async throws -> ModelTurn {
        calls += 1
        return .final("unexpected")
    }
}
