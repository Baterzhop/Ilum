import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IlumCore

final class OllamaStreamingTests: XCTestCase {
    func testFragmentedUTF8AndCoalescedFramesProduceProgressAndBoundedNativeRequest() async throws {
        let source = """
        {"message":{"role":"assistant","thinking":"private trace","content":""},"done":false}
        {"message":{"content":"Привіт 🌍"},"done":false}
        {"message":{"content":"!"},"done":true,"done_reason":"stop"}
        """
        let transport = ScriptedStreamTransport([source.utf8.map { Data([$0]) }])
        let recorder = ProgressRecorder()
        let turn = try await OllamaChatProvider(model: "qwen3:4b", transport: transport).respond(
            to: ModelRequest(messages: [ChatMessage(role: .user, content: "hello")], maxOutputTokens: 256),
            onProgress: { await recorder.record($0) }
        )
        guard case .final(let answer) = turn else { return XCTFail("Expected final") }
        XCTAssertEqual(answer, "Привіт 🌍!")
        let events = await recorder.values()
        let contentEvents = events.filter { if case .metrics = $0 { return false }; return true }
        XCTAssertEqual(contentEvents, [.thinking, .textDelta("Привіт 🌍"), .textDelta("!")])
        XCTAssertEqual(events.filter { if case .metrics = $0 { return true }; return false }.count, 1)
        let payload = try payload(transport.requests()[0])
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual(payload["think"] as? Bool, false)
        XCTAssertEqual((payload["options"] as? [String: Any])?["num_predict"] as? Int, 256)
        XCTAssertEqual(transport.cancellations(), 1)
    }

    func testTerminalMetricsConvertNanosecondsAndMeasureFirstVisibleText() async throws {
        let source = """
        {"message":{"thinking":"reasoning only"},"done":false}
        {"message":{"content":"answer"},"done":false}
        {"message":{"content":""},"done":true,"done_reason":"stop","total_duration":6000000000,"load_duration":1000000000,"prompt_eval_duration":2000000000,"eval_duration":3000000000,"prompt_eval_count":120,"eval_count":60}
        """
        let recorder = ProgressRecorder()
        _ = try await OllamaChatProvider(model: "test", transport: ScriptedStreamTransport([[Data(source.utf8)]])).respond(
            to: ModelRequest(messages: []), onProgress: { await recorder.record($0) }
        )
        let events = await recorder.values()
        let metrics = try XCTUnwrap(events.compactMap { if case .metrics(let value) = $0 { return value }; return nil }.first)
        XCTAssertEqual(metrics.serverTotalSeconds, 6)
        XCTAssertEqual(metrics.loadSeconds, 1)
        XCTAssertEqual(metrics.promptSeconds, 2)
        XCTAssertEqual(metrics.generationSeconds, 3)
        XCTAssertEqual(metrics.promptTokens, 120)
        XCTAssertEqual(metrics.generatedTokens, 60)
        XCTAssertEqual(metrics.generatedTokensPerSecond, 20)
        XCTAssertNotNil(metrics.firstTextSeconds)
        XCTAssertGreaterThanOrEqual(metrics.requestSeconds, metrics.firstTextSeconds ?? 0)
    }

    func testOptionalMalformedTelemetryDoesNotDiscardAnswerOrFabricateZeroMeasurements() async throws {
        let source = """
        {"message":{"content":"complete"},"done":true,"load_duration":-1,"prompt_eval_duration":"bad","eval_duration":0,"eval_count":40,"prompt_eval_count":-10}
        """
        let recorder = ProgressRecorder()
        let turn = try await OllamaChatProvider(model: "test", transport: ScriptedStreamTransport([[Data(source.utf8)]])).respond(
            to: ModelRequest(messages: []), onProgress: { await recorder.record($0) }
        )
        guard case .final("complete") = turn else { return XCTFail("Telemetry must not break the answer") }
        let events = await recorder.values()
        let metrics = try XCTUnwrap(events.compactMap { if case .metrics(let value) = $0 { return value }; return nil }.first)
        XCTAssertNil(metrics.serverTotalSeconds)
        XCTAssertNil(metrics.loadSeconds)
        XCTAssertNil(metrics.promptSeconds)
        XCTAssertNil(metrics.promptTokens)
        XCTAssertNil(metrics.generatedTokensPerSecond)
    }

    func testInterruptedStreamDoesNotEmitCompletionMetrics() async throws {
        let recorder = ProgressRecorder()
        let source = "{\"message\":{\"content\":\"partial\"},\"done\":false,\"eval_count\":10}\n"
        do {
            _ = try await OllamaChatProvider(model: "test", transport: ScriptedStreamTransport([[Data(source.utf8)]])).respond(
                to: ModelRequest(messages: []), onProgress: { await recorder.record($0) }
            )
            XCTFail("Expected incomplete stream")
        } catch is ModelProviderError { }
        let events = await recorder.values()
        XCTAssertFalse(events.contains { if case .metrics = $0 { return true }; return false })
    }

    func testThinkingProfilesUseNativeFieldsIncludingGPTOSSLevels() async throws {
        for (model, mode, expected) in [
            ("qwen3:4b", OllamaThinkingMode.thinking, JSONValue.bool(true)),
            ("gpt-oss:20b", .fast, .string("low")),
            ("gpt-oss:20b", .thinking, .string("high"))
        ] {
            let transport = ScriptedStreamTransport([[Data(finalFrame.utf8)]])
            _ = try await OllamaChatProvider(model: model, thinkingMode: mode, transport: transport)
                .respond(to: ModelRequest(messages: []))
            let data = try XCTUnwrap(transport.requests().first?.httpBody)
            guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: data) else { return XCTFail() }
            XCTAssertEqual(body["think"], expected)
        }
        let transport = ScriptedStreamTransport([[Data(finalFrame.utf8)]])
        _ = try await OllamaChatProvider(model: "llama3.2", thinkingMode: .modelDefault, transport: transport)
            .respond(to: ModelRequest(messages: []))
        XCTAssertNil(try payload(transport.requests()[0])["think"])
    }

    func testInterruptedTruncatedMalformedAndErrorStreamsNeverPersistAnAssistant() async throws {
        let frames = [
            "{\"message\":{\"content\":\"partial\"},\"done\":false}\n",
            "{\"message\":{\"content\":\"partial\"},\"done\":true,\"done_reason\":\"length\"}\n",
            "{\"message\":{\"content\":\"partial\"},\"done\":false}\nnot-json\n",
            "{\"error\":\"model unavailable\"}\n"
        ]
        for frame in frames {
            let store = StreamingTestStore()
            let transport = ScriptedStreamTransport([[Data(frame.utf8)]])
            let runtime = AgentRuntime(store: store, model: OllamaChatProvider(model: "test", transport: transport))
            let id = UUID()
            do { _ = try await runtime.send("hello", conversationID: id); XCTFail("Must reject incomplete/error response") }
            catch is ModelProviderError { }
            let conversation = try await store.loadConversation(id: id)
            XCTAssertEqual(conversation?.messages.map(\.role), [.user])
            XCTAssertEqual(transport.cancellations(), 1)
        }
    }

    func testHTTPFailureAndOversizedFrameAreExplicit() async throws {
        let failed = ScriptedStreamTransport([[Data("missing model".utf8)]], status: 404)
        do {
            _ = try await OllamaChatProvider(model: "test", transport: failed).respond(to: ModelRequest(messages: []))
            XCTFail("Must reject HTTP error")
        } catch let error as ModelProviderError {
            guard case .server(status: 404, body: "missing model") = error else { return XCTFail("\(error)") }
        }
        let huge = ScriptedStreamTransport([[Data(repeating: 0x61, count: 1_024 * 1_024 + 1)]])
        do {
            _ = try await OllamaChatProvider(model: "test", transport: huge).respond(to: ModelRequest(messages: []))
            XCTFail("Must cap unterminated frames")
        } catch let error as ModelProviderError {
            guard case .responseTooLarge = error else { return XCTFail("\(error)") }
        }
    }

    func testMalformedUnknownMultipleAndTruncatedToolCallsAreRejected() async throws {
        let name = ReadTextFileTool.descriptor.wireName
        let valid = "{\"function\":{\"name\":\"\(name)\",\"arguments\":{\"resourceID\":\"selected\"}}}"
        let cases = [
            ("{\"function\":{\"name\":\"shell_exec\",\"arguments\":{}}}", "stop"),
            ("{\"function\":{\"name\":\"\(name)\",\"arguments\":\"{}\"}}", "stop"),
            (valid + "," + valid, "stop"),
            (valid, "length")
        ]
        for (calls, reason) in cases {
            let frame = "{\"message\":{\"tool_calls\":[\(calls)]},\"done\":true,\"done_reason\":\"\(reason)\"}\n"
            let transport = ScriptedStreamTransport([[Data(frame.utf8)]])
            do {
                _ = try await OllamaChatProvider(model: "test", transport: transport).respond(to: ModelRequest(
                    messages: [], availableTools: [ReadTextFileTool.descriptor]
                ))
                XCTFail("Must reject unsafe tool response")
            } catch is ModelProviderError { }
        }
    }

    func testPartialToolCallCannotReachPermissionGateBeforeDone() async throws {
        let transport = ScriptedStreamTransport([[Data(toolFrame(done: false).utf8)]])
        let store = StreamingTestStore()
        let runtime = try makeRuntime(store: store, transport: transport)
        let id = UUID()
        do { _ = try await runtime.send("read", conversationID: id); XCTFail("Requires done") }
        catch let error as ModelProviderError {
            guard case .incompleteStream = error else { return XCTFail("\(error)") }
        }
        let pending = try await runtime.restorePendingPermission(conversationID: id)
        XCTAssertNil(pending)
    }

    func testNativeToolContextSurvivesRestartAndApproveOrDeny() async throws {
        for approve in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SQLiteConversationStore(url: root.appendingPathComponent("chat.sqlite3"))
            let transport = ScriptedStreamTransport([
                [Data(toolFrame(done: true).utf8)], [Data(finalFrame.utf8)]
            ])
            let runtime = try makeRuntime(store: store, transport: transport, pendingStore: store)
            let id = UUID()
            guard case .permissionRequired(let pending) = try await runtime.send("read", conversationID: id) else {
                return XCTFail("Explicit permission required")
            }
            let before = try await store.loadConversation(id: id)
            XCTAssertEqual(before?.messages.map(\.role), [.user])
            let restored = try makeRuntime(store: store, transport: transport, pendingStore: store)
            let progress = RuntimeProgressRecorder()
            let outcome: RuntimeOutcome
            if approve {
                outcome = try await restored.approvePermission(pendingID: pending.id, duration: .once, onProgress: { await progress.record($0) })
            } else {
                outcome = try await restored.denyPermission(pendingID: pending.id, onProgress: { await progress.record($0) })
            }
            guard case .completed(let response) = outcome else { return XCTFail("Must complete") }
            XCTAssertEqual(response.conversation.messages.map(\.role), [.user, .tool, .assistant])
            let events = await progress.text()
            XCTAssertEqual(events, "complete")
            let messages = try XCTUnwrap(try payload(transport.requests()[1])["messages"] as? [[String: Any]])
            let assistant = try XCTUnwrap(messages.first(where: { $0["tool_calls"] != nil }))
            XCTAssertEqual(assistant["thinking"] as? String, "tool reasoning")
            XCTAssertEqual(assistant["content"] as? String, "I can read it.")
            let tool = try XCTUnwrap(messages.first(where: { $0["role"] as? String == "tool" }))
            XCTAssertEqual(tool["tool_name"] as? String, ReadTextFileTool.descriptor.wireName)
            let result = try XCTUnwrap(tool["content"] as? String)
            XCTAssertFalse(result.contains("tool reasoning"))
            XCTAssertEqual(result.contains("file contents"), approve)
            XCTAssertTrue(result.contains(approve ? "success" : "denied"))
        }
    }

    func testCancellationAfterPreviewDiscardsAnswerAndClosesConnection() async throws {
        let transport = ControlledStreamTransport()
        let store = StreamingTestStore()
        let runtime = AgentRuntime(store: store, model: OllamaChatProvider(model: "test", transport: transport))
        let preview = expectation(description: "Preview arrives before the stream finishes")
        let id = UUID()
        let task = Task {
            try await runtime.send("hello", conversationID: id, onProgress: { event in
                if case .model(.textDelta("partial")) = event { preview.fulfill() }
            })
        }
        await fulfillment(of: [preview], timeout: 5)
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") }
        catch is CancellationError { }
        let conversation = try await store.loadConversation(id: id)
        XCTAssertEqual(conversation?.messages.map(\.role), [.user])
        XCTAssertTrue(transport.wasCancelled())
    }

    func testCancellationAfterApprovalRetainsToolResultAndClearsPendingExecution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("chat.sqlite3"))
        let initial = try makeRuntime(store: store, transport: ScriptedStreamTransport([[Data(toolFrame(done: true).utf8)]]), pendingStore: store)
        let id = UUID()
        guard case .permissionRequired(let pending) = try await initial.send("read", conversationID: id) else {
            return XCTFail("Expected permission")
        }
        let transport = ControlledStreamTransport()
        let resumed = try makeRuntime(store: store, transport: transport, pendingStore: store)
        let preview = expectation(description: "Continuation has started after the approved tool")
        let task = Task {
            try await resumed.approvePermission(pendingID: pending.id, duration: .once, onProgress: { event in
                if case .model(.textDelta("partial")) = event { preview.fulfill() }
            })
        }
        await fulfillment(of: [preview], timeout: 5)
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel generation") }
        catch is CancellationError { }
        let conversation = try await store.loadConversation(id: id)
        XCTAssertEqual(conversation?.messages.map(\.role), [.user, .tool])
        XCTAssertTrue(conversation?.messages.last?.content.contains("file contents") ?? false)
        let stillPending = try await store.loadPendingExecution(conversationID: id)
        XCTAssertNil(stillPending)
        XCTAssertTrue(transport.wasCancelled())
    }

    func testRuntimeRejectsFinalFromProviderThatIgnoresCancellation() async throws {
        let store = StreamingTestStore()
        let runtime = AgentRuntime(store: store, model: CancellationIgnoringModel())
        let id = UUID()
        let task = Task { try await runtime.send("hello", conversationID: id) }
        do { _ = try await task.value; XCTFail("Must not commit final") }
        catch is CancellationError { }
        let conversation = try await store.loadConversation(id: id)
        XCTAssertFalse(conversation?.messages.contains(where: { $0.role == .assistant }) ?? false)
    }

    func testLegacyToolPayloadsDecodeWithoutAssistantContext() throws {
        let call = try ToolCall.encoding(name: "file.readText", version: "2", input: ReadTextFileInput(resourceID: .init(rawValue: "selected")))
        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertNil(decoded.assistantContext)
        let event = ToolHistoryEvent(status: .denied, callID: call.id, providerCallID: call.providerCallID,
                                     tool: call.name, version: call.version, arguments: .object([:]))
        XCTAssertNil(try JSONDecoder().decode(ToolHistoryEvent.self, from: JSONEncoder().encode(event)).assistantContext)
    }

    private func makeRuntime(store: any ConversationStore, transport: any HTTPStreamingTransport,
                             pendingStore: (any PendingExecutionStore)? = nil) throws -> AgentRuntime {
        AgentRuntime(store: store, model: OllamaChatProvider(model: "qwen3:4b", transport: transport),
                     toolRuntime: ToolRuntime(registry: try ToolRegistry(tools: [AnyTool(StreamingFileBrokerTool())]), permissions: PermissionEngine()),
                     pendingExecutionStore: pendingStore)
    }

    private var finalFrame: String { "{\"message\":{\"content\":\"complete\"},\"done\":true,\"done_reason\":\"stop\"}\n" }
    private func toolFrame(done: Bool) -> String {
        "{\"message\":{\"content\":\"I can read it.\",\"thinking\":\"tool reasoning\",\"tool_calls\":[{\"function\":{\"index\":0,\"name\":\"\(ReadTextFileTool.descriptor.wireName)\",\"arguments\":{\"resourceID\":\"selected\"}}}]},\"done\":\(done),\"done_reason\":\"stop\"}\n"
    }
    private func payload(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

private final class ScriptedStreamTransport: HTTPStreamingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [[Data]]
    private let status: Int
    private var captured: [URLRequest] = []
    private var cancelled = 0
    init(_ scripts: [[Data]], status: Int = 200) { self.scripts = scripts; self.status = status }
    func open(_ request: URLRequest) -> HTTPEventStream {
        lock.lock()
        captured.append(request)
        let chunks = scripts.isEmpty ? [] : scripts.removeFirst()
        lock.unlock()
        let events = AsyncThrowingStream<HTTPStreamEvent, Error> { continuation in
            continuation.yield(.response(statusCode: status))
            for chunk in chunks { continuation.yield(.data(chunk)) }
            continuation.finish()
        }
        return HTTPEventStream(events: events, cancel: { self.cancel() })
    }
    private func cancel() { lock.lock(); cancelled += 1; lock.unlock() }
    func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    func cancellations() -> Int { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private final class ControlledStreamTransport: HTTPStreamingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation?
    private var cancelled = false
    func open(_ request: URLRequest) -> HTTPEventStream {
        let events = AsyncThrowingStream<HTTPStreamEvent, Error> { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
            continuation.yield(.response(statusCode: 200))
            continuation.yield(.data(Data("{\"message\":{\"content\":\"partial\"},\"done\":false}\n".utf8)))
        }
        return HTTPEventStream(events: events, cancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.finish(throwing: CancellationError())
    }
    func wasCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private actor ProgressRecorder {
    var events: [ModelProgress] = []
    func record(_ event: ModelProgress) { events.append(event) }
    func values() -> [ModelProgress] { events }
}
private actor RuntimeProgressRecorder {
    var content = ""
    func record(_ event: RuntimeProgress) { if case .model(.textDelta(let delta)) = event { content += delta } }
    func text() -> String { content }
}
private actor StreamingTestStore: ConversationStore {
    var conversations: [UUID: Conversation] = [:]
    func saveConversation(_ conversation: Conversation) async throws { conversations[conversation.id] = conversation }
    func loadConversation(id: UUID) async throws -> Conversation? { conversations[id] }
}
private struct CancellationIgnoringModel: ModelProvider {
    func respond(to request: ModelRequest) async throws -> ModelTurn {
        withUnsafeCurrentTask { $0?.cancel() }
        return .final("must not persist")
    }
}
private struct StreamingFileBrokerTool: Tool {
    static let descriptor = ReadTextFileTool.descriptor
    func resource(for input: ReadTextFileInput) throws -> ResourceScope { .userFile(input.resourceID) }
    func execute(_ input: ReadTextFileInput) async throws -> ReadTextFileOutput {
        ReadTextFileOutput(resourceID: input.resourceID, displayName: "selected.txt", content: "file contents", byteCount: 13, truncated: false)
    }
}
