import XCTest
@testable import IlumCore

final class AgentConcurrencyTests: XCTestCase {
    func testSecondSendToSameConversationFailsWhileFirstTurnIsSuspended() async throws {
        let conversationID = UUID()
        let store = try SQLiteConversationStore(url: temporaryURL("same-conversation.sqlite3"))
        let gate = AsyncGate()
        let model = SelectiveBlockingModel(gate: gate)
        let runtime = AgentRuntime(store: store, model: model)

        let first = Task {
            try await runtime.send("block", conversationID: conversationID)
        }
        await gate.waitUntilEntered()

        do {
            _ = try await runtime.send("must not interleave", conversationID: conversationID)
            XCTFail("A second turn in the same conversation must fail while the first turn is active")
        } catch let error as AgentRuntimeError {
            guard case .concurrentConversationRun(let blockedID) = error else {
                return XCTFail("Unexpected runtime error: \(error)")
            }
            XCTAssertEqual(blockedID, conversationID)
        }

        await gate.open()
        guard case .completed(let response) = try await first.value else {
            return XCTFail("Expected the original turn to complete")
        }
        XCTAssertEqual(response.assistantMessage.content, "block completed")

        let persisted = try await store.loadConversation(id: conversationID)
        XCTAssertEqual(persisted?.messages.map(\.role), [.user, .assistant])
        XCTAssertFalse(persisted?.messages.contains(where: { $0.content == "must not interleave" }) ?? true)
    }

    func testDifferentConversationCanRunWhileAnotherConversationIsSuspended() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let store = try SQLiteConversationStore(url: temporaryURL("different-conversations.sqlite3"))
        let gate = AsyncGate()
        let model = SelectiveBlockingModel(gate: gate)
        let runtime = AgentRuntime(store: store, model: model)

        let first = Task {
            try await runtime.send("block", conversationID: firstID)
        }
        await gate.waitUntilEntered()

        let second = try await runtime.send("independent", conversationID: secondID)
        guard case .completed(let secondResponse) = second else {
            return XCTFail("Expected independent conversation to complete")
        }
        XCTAssertEqual(secondResponse.assistantMessage.content, "independent completed")

        await gate.open()
        guard case .completed = try await first.value else {
            return XCTFail("Expected blocked conversation to complete after release")
        }
    }

    func testPermissionContinuationKeepsConversationLeaseAfterPendingRecordResolves() async throws {
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "concurrency-file")
        let store = try SQLiteConversationStore(url: temporaryURL("permission-continuation.sqlite3"))
        let gate = AsyncGate()
        let model = PermissionContinuationModel(resourceID: resourceID, continuationGate: gate)
        let broker = ConcurrencyFileBroker(resourceID: resourceID, content: "tool data")
        let toolRuntime = ToolRuntime(
            registry: try ToolRegistry(tools: [AnyTool(ReadTextFileTool(broker: broker))]),
            permissions: PermissionEngine()
        )
        let runtime = AgentRuntime(
            store: store,
            model: model,
            toolRuntime: toolRuntime,
            pendingExecutionStore: store
        )

        let initial = try await runtime.send("read then continue", conversationID: conversationID)
        guard case .permissionRequired(let pending) = initial else {
            return XCTFail("Expected permission request")
        }

        let approval = Task {
            try await runtime.approvePermission(pendingID: pending.id, duration: .once)
        }
        await gate.waitUntilEntered()

        let pendingAfterToolResolution = try await store.loadPendingExecution(conversationID: conversationID)
        XCTAssertNil(pendingAfterToolResolution, "The regression point requires the durable pending row to already be resolved")

        do {
            _ = try await runtime.send("race after pending deletion", conversationID: conversationID)
            XCTFail("The permission continuation must keep the conversation lease after pending deletion")
        } catch let error as AgentRuntimeError {
            guard case .concurrentConversationRun(let blockedID) = error else {
                return XCTFail("Unexpected runtime error: \(error)")
            }
            XCTAssertEqual(blockedID, conversationID)
        }

        await gate.open()
        guard case .completed(let response) = try await approval.value else {
            return XCTFail("Expected permission continuation to complete")
        }
        XCTAssertEqual(response.assistantMessage.content, "permission continuation completed")

        let persisted = try await store.loadConversation(id: conversationID)
        XCTAssertEqual(persisted?.messages.map(\.role), [.user, .tool, .assistant])
        XCTAssertFalse(persisted?.messages.contains(where: { $0.content == "race after pending deletion" }) ?? true)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-concurrency-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

private actor AsyncGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private struct SelectiveBlockingModel: ModelProvider, Sendable {
    let gate: AsyncGate

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        let text = request.messages.last(where: { $0.role == .user })?.content ?? ""
        if text == "block" {
            await gate.wait()
            return .final("block completed")
        }
        return .final("independent completed")
    }
}

private actor PermissionContinuationModel: ModelProvider {
    let resourceID: UserFileResourceID
    let continuationGate: AsyncGate
    private var calls = 0

    init(resourceID: UserFileResourceID, continuationGate: AsyncGate) {
        self.resourceID = resourceID
        self.continuationGate = continuationGate
    }

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        calls += 1
        if calls == 1 {
            return .toolCall(
                try ToolCall.encoding(
                    name: "file.readText",
                    version: "2",
                    input: ReadTextFileInput(resourceID: resourceID)
                )
            )
        }

        guard request.messages.contains(where: { $0.role == .tool }) else {
            throw ConcurrencyTestError.toolResultMissing
        }
        await continuationGate.wait()
        return .final("permission continuation completed")
    }
}

private struct ConcurrencyFileBroker: UserFileAccessBroker, Sendable {
    let resourceID: UserFileResourceID
    let content: String

    func descriptor(for id: UserFileResourceID) throws -> UserFileDescriptor {
        guard id == resourceID else { throw UserFileAccessError.unknownResource(id) }
        return UserFileDescriptor(
            id: id,
            displayName: "concurrency.txt",
            locationHint: "/user-selected/concurrency.txt"
        )
    }

    func readText(resourceID: UserFileResourceID, maxBytes: Int) async throws -> UserFileTextRead {
        let descriptor = try descriptor(for: resourceID)
        let bytes = Data(content.utf8)
        return UserFileTextRead(
            descriptor: descriptor,
            content: content,
            byteCount: min(bytes.count, maxBytes),
            truncated: bytes.count > maxBytes
        )
    }
}

private enum ConcurrencyTestError: Error {
    case toolResultMissing
}
