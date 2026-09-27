import XCTest
@testable import IlumCore

final class AgentRuntimeTests: XCTestCase {
    func testUserInputIsDurableBeforeModelExecution() async throws {
        let conversationID = UUID()
        let store = TestConversationStore()
        let model = PersistenceCheckingModel(
            store: store,
            conversationID: conversationID,
            expectedUserText: "persist me first"
        )
        let runtime = AgentRuntime(store: store, model: model)

        let outcome = try await runtime.send(
            "persist me first",
            conversationID: conversationID
        )

        guard case .completed(let response) = outcome else {
            return XCTFail("Expected completed response")
        }
        XCTAssertEqual(response.assistantMessage.content, "durability confirmed")

        let persisted = try await store.loadConversation(id: conversationID)
        XCTAssertEqual(persisted?.messages.map(\.role), [.user, .assistant])
    }

    func testFileContentDoesNotReachModelBeforeExplicitApproval() async throws {
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "selected-file")
        let secret = "private file content"
        let store = TestConversationStore()
        let model = FileReadingModel(resourceID: resourceID, secret: secret)
        let broker = TestFileBroker(resourceID: resourceID, content: secret)
        let permissions = PermissionEngine()
        let registry = try ToolRegistry(tools: [
            AnyTool(ReadTextFileTool(broker: broker))
        ])
        let toolRuntime = ToolRuntime(registry: registry, permissions: permissions)
        let runtime = AgentRuntime(
            store: store,
            model: model,
            toolRuntime: toolRuntime
        )

        let first = try await runtime.send(
            "Read my selected file",
            conversationID: conversationID
        )

        guard case .permissionRequired(let pending) = first else {
            return XCTFail("Expected permission request")
        }

        let beforeApproval = try await store.loadConversation(id: conversationID)
        XCTAssertEqual(beforeApproval?.messages.count, 1)
        XCTAssertFalse(beforeApproval?.messages.contains(where: {
            $0.content.contains(secret)
        }) ?? true)

        let second = try await runtime.approvePermission(
            pendingID: pending.id,
            duration: .once
        )

        guard case .completed(let response) = second else {
            return XCTFail("Expected completion after approval")
        }
        XCTAssertEqual(response.assistantMessage.content, "file read completed")
        XCTAssertTrue(response.conversation.messages.contains(where: {
            $0.role == .tool && $0.content.contains(secret)
        }))
    }

    func testChatTextCannotApprovePendingToolCall() async throws {
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "selected-file")
        let store = TestConversationStore()
        let model = FileReadingModel(resourceID: resourceID, secret: "secret")
        let broker = TestFileBroker(resourceID: resourceID, content: "secret")
        let toolRuntime = ToolRuntime(
            registry: try ToolRegistry(tools: [AnyTool(ReadTextFileTool(broker: broker))]),
            permissions: PermissionEngine()
        )
        let runtime = AgentRuntime(store: store, model: model, toolRuntime: toolRuntime)

        let first = try await runtime.send("Read it", conversationID: conversationID)
        guard case .permissionRequired = first else {
            return XCTFail("Expected permission request")
        }

        do {
            _ = try await runtime.send(
                "I approve this in chat",
                conversationID: conversationID
            )
            XCTFail("Chat text must not authorize a pending action")
        } catch let error as AgentRuntimeError {
            guard case .pendingPermissionExists = error else {
                return XCTFail("Unexpected runtime error: \(error)")
            }
        }
    }
}

private actor TestConversationStore: ConversationStore {
    private var conversations: [UUID: Conversation] = [:]

    func loadConversation(id: UUID) async throws -> Conversation? {
        conversations[id]
    }

    func saveConversation(_ conversation: Conversation) async throws {
        conversations[conversation.id] = conversation
    }
}

private struct PersistenceCheckingModel: ModelProvider, Sendable {
    let store: TestConversationStore
    let conversationID: UUID
    let expectedUserText: String

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        let persisted = try await store.loadConversation(id: conversationID)
        guard persisted?.messages.last?.role == .user,
              persisted?.messages.last?.content == expectedUserText else {
            throw TestRuntimeError.userWasNotPersistedFirst
        }
        return .final("durability confirmed")
    }
}

private actor FileReadingModel: ModelProvider {
    let resourceID: UserFileResourceID
    let secret: String
    private var calls = 0

    init(resourceID: UserFileResourceID, secret: String) {
        self.resourceID = resourceID
        self.secret = secret
    }

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        calls += 1
        if calls == 1 {
            XCTAssertFalse(request.messages.contains(where: {
                $0.content.contains(secret)
            }))
            return .toolCall(
                try ToolCall.encoding(
                    name: "file.readText",
                    version: "2",
                    input: ReadTextFileInput(resourceID: resourceID)
                )
            )
        }

        guard request.messages.contains(where: {
            $0.role == .tool && $0.content.contains(secret)
        }) else {
            throw TestRuntimeError.toolResultMissingAfterApproval
        }
        return .final("file read completed")
    }
}

private struct TestFileBroker: UserFileAccessBroker, Sendable {
    let resourceID: UserFileResourceID
    let content: String

    func descriptor(for id: UserFileResourceID) throws -> UserFileDescriptor {
        guard id == resourceID else {
            throw UserFileAccessError.unknownResource(id)
        }
        return UserFileDescriptor(
            id: id,
            displayName: "selected.txt",
            locationHint: "/user-selected/selected.txt"
        )
    }

    func readText(
        resourceID: UserFileResourceID,
        maxBytes: Int
    ) async throws -> UserFileTextRead {
        let descriptor = try descriptor(for: resourceID)
        let data = Data(content.utf8)
        return UserFileTextRead(
            descriptor: descriptor,
            content: content,
            byteCount: min(data.count, maxBytes),
            truncated: data.count > maxBytes
        )
    }
}

private enum TestRuntimeError: Error {
    case userWasNotPersistedFirst
    case toolResultMissingAfterApproval
}
