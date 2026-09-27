import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IlumCore

final class FullContextBudgetTests: XCTestCase {
    private let manager = ContextBudgetManager(policy: ContextBudgetPolicy(
        contextWindow: 1024, reservedOutputTokens: 128, safetyMarginTokens: 64,
        fixedSystemTokens: 0, perMessageOverheadTokens: 6
    ))

    func testOversizedSystemPromptFailsEvenWithEmptyHistory() throws {
        let model = OpenAICompatibleProvider(systemPrompt: String(repeating: "x", count: 3000))
        let pack = try manager.pack(request: ModelRequest(messages: []), model: model)
        XCTAssertFalse(pack.report.fits)
        XCTAssertGreaterThan(pack.report.estimatedInputTokens, 832)
        XCTAssertEqual(pack.report.inputBudgetTokens, 0)
    }

    func testToolDefinitionsReduceSpaceForOldTurns() throws {
        let model = OpenAICompatibleProvider(systemPrompt: "brief")
        let messages = [
            ChatMessage(role: .user, content: String(repeating: "x", count: 500)),
            ChatMessage(role: .assistant, content: String(repeating: "y", count: 500)),
            ChatMessage(role: .user, content: "latest request")
        ]
        let plain = try manager.pack(request: ModelRequest(messages: messages), model: model)
        let base = ReadTextFileTool.descriptor
        let tool = ToolDescriptor(name: base.name, version: base.version,
            summary: String(repeating: "s", count: 1500), risk: base.risk,
            capability: base.capability, inputSchema: base.inputSchema)
        let withTools = try manager.pack(request: ModelRequest(messages: messages, availableTools: [tool]), model: model)
        XCTAssertEqual(plain.messages.count, 3)
        XCTAssertLessThan(withTools.messages.count, plain.messages.count)
        XCTAssertEqual(withTools.messages.last?.id, messages.last?.id)
        XCTAssertLessThan(withTools.report.inputBudgetTokens, plain.report.inputBudgetTokens)
    }

    func testGroundedPolicyAndEvidenceAreBothBudgeted() throws {
        let hit = KnowledgeHit(documentID: UUID(), sourceResourceID: UserFileResourceID(rawValue: "file"),
            displayName: "manual.pdf", chunkID: UUID(), chunkOrdinal: 0, pageStart: 1, pageEnd: 1,
            score: 1, text: "A quoted fact with a newline.\nAnother line.")
        let context = try GroundedContextBuilder().build(from: [hit])
        let messages = [ChatMessage(role: .user, content: "What is the fact?")]
        let model = OllamaChatProvider(model: "test")
        let plain = try XCTUnwrap(model.contextCosts(for: ModelRequest(messages: messages),
            estimator: HeuristicTokenEstimator(), messageOverhead: 6))
        let grounded = try XCTUnwrap(model.contextCosts(for: ModelRequest(messages: messages, groundedContext: context),
            estimator: HeuristicTokenEstimator(), messageOverhead: 6))
        XCTAssertGreaterThan(grounded.fixedTokens, plain.fixedTokens)
        XCTAssertGreaterThan(grounded.knowledgeTokens, 0)
        XCTAssertEqual(grounded.messageTokens, plain.messageTokens)
    }

    func testNativeToolAssistantThinkingAndArgumentsConsumeContext() throws {
        func request(thinking: String) throws -> ModelRequest {
            let event = ToolHistoryEvent(status: .success, callID: UUID(), providerCallID: "call-test",
                tool: "file.readText", version: "1", arguments: .object(["resourceID": .string("file")]),
                data: .string("result"), assistantContext: ToolAssistantContext(content: "", thinking: thinking))
            let message = ChatMessage(role: .tool, content: String(decoding: try JSONEncoder().encode(event), as: UTF8.self))
            return ModelRequest(messages: [ChatMessage(role: .user, content: "read"), message])
        }
        let model = OllamaChatProvider(model: "test")
        let plain = try XCTUnwrap(model.contextCosts(for: request(thinking: ""), estimator: HeuristicTokenEstimator(), messageOverhead: 6))
        let large = try XCTUnwrap(model.contextCosts(for: request(thinking: String(repeating: "x", count: 3000)), estimator: HeuristicTokenEstimator(), messageOverhead: 6))
        XCTAssertGreaterThan(large.messageTokens[1], plain.messageTokens[1] + 900)
        let pack = try manager.pack(request: request(thinking: String(repeating: "x", count: 3000)), model: model)
        XCTAssertFalse(pack.report.fits)
        XCTAssertEqual(pack.messages.map(\.role), [.user, .tool])
    }

    func testSystemOverflowStopsBeforeNetworkAndPreservesQuestion() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ilum-full-budget-\(UUID())/chat.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let transport = BudgetCountingTransport()
        let runtime = AgentRuntime(store: store,
            model: OpenAICompatibleProvider(systemPrompt: String(repeating: "x", count: 4000), transport: transport),
            contextBudgetManager: manager)
        let id = UUID()
        do {
            _ = try await runtime.send("keep this", conversationID: id)
            XCTFail("Must reject the oversized system prompt")
        } catch let error as AgentRuntimeError {
            guard case .contextBudgetExceeded = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
        let chat = try await store.loadConversation(id: id)
        XCTAssertEqual(chat?.messages.map(\.content), ["keep this"])
    }
}

private actor BudgetCountingTransport: HTTPTransport {
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        calls += 1
        throw ModelProviderError.invalidResponse
    }
}
