import Foundation
import XCTest
@testable import IlumCore

final class PersonalMemoryAgentIntegrationTests: XCTestCase {
    func testAgentPausesBeforePersonalMemoryWriteAndResumesExactTurn() async throws {
        let memory = try SQLitePersonalMemoryStore(url: temporaryURL("remember.sqlite3"))
        let conversationStore = MemoryIntegrationConversationStore()
        let model = MemoryRememberingModel()
        let permissions = PermissionEngine(automaticallyAllowedCapabilities: [.readAppData])
        let tools = ToolRuntime(
            registry: try ToolRegistry(tools: [
                AnyTool(MemorySearchTool(store: memory)),
                AnyTool(MemoryRememberTool(store: memory))
            ]),
            permissions: permissions
        )
        let runtime = AgentRuntime(
            store: conversationStore,
            model: model,
            toolRuntime: tools
        )
        let conversationID = UUID()

        let first = try await runtime.send(
            "Remember that I prefer concise technical answers.",
            conversationID: conversationID
        )
        guard case .permissionRequired(let pending) = first else {
            return XCTFail("A Personal Memory write must pause for explicit approval")
        }

        let beforeApproval = try await memory.search("concise technical", limit: 5)
        XCTAssertTrue(beforeApproval.isEmpty)
        XCTAssertEqual(pending.permission.capability, .writeAppData)
        XCTAssertEqual(pending.permission.resource, .appData("personal-memory"))

        let second = try await runtime.approvePermission(
            pendingID: pending.id,
            duration: .once
        )
        guard case .completed(let response) = second else {
            return XCTFail("The same agent turn should complete after approval")
        }

        XCTAssertEqual(response.assistantMessage.content, "Saved to Personal Memory.")
        let afterApproval = try await memory.search("concise technical", limit: 5)
        XCTAssertEqual(afterApproval.count, 1)
        XCTAssertEqual(afterApproval.first?.kind, .preference)

        let persisted = try await conversationStore.loadConversation(id: conversationID)
        XCTAssertTrue(persisted?.messages.contains(where: {
            $0.role == .tool && $0.content.contains("memory.remember")
        }) ?? false)
    }

    func testAgentCanRecallApprovedPersonalMemoryWithoutPermissionPrompt() async throws {
        let memory = try SQLitePersonalMemoryStore(url: temporaryURL("recall.sqlite3"))
        _ = try await memory.remember(
            content: "The user prefers Ukrainian replies.",
            kind: .preference,
            tags: ["language"],
            importance: 0.9
        )

        let conversationStore = MemoryIntegrationConversationStore()
        let model = MemoryRecallingModel(expectedMemoryText: "prefers Ukrainian replies")
        let permissions = PermissionEngine(automaticallyAllowedCapabilities: [.readAppData])
        let tools = ToolRuntime(
            registry: try ToolRegistry(tools: [
                AnyTool(MemorySearchTool(store: memory))
            ]),
            permissions: permissions
        )
        let runtime = AgentRuntime(
            store: conversationStore,
            model: model,
            toolRuntime: tools
        )

        let outcome = try await runtime.send(
            "Which language do I prefer?",
            conversationID: UUID()
        )
        guard case .completed(let response) = outcome else {
            return XCTFail("Read-only Personal Memory recall should not stop for approval")
        }
        XCTAssertEqual(response.assistantMessage.content, "You prefer Ukrainian replies.")
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-memory-agent-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

private actor MemoryIntegrationConversationStore: ConversationStore {
    private var conversations: [UUID: Conversation] = [:]

    func loadConversation(id: UUID) async throws -> Conversation? {
        conversations[id]
    }

    func saveConversation(_ conversation: Conversation) async throws {
        conversations[conversation.id] = conversation
    }
}

private actor MemoryRememberingModel: ModelProvider {
    private var callCount = 0

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        callCount += 1
        if callCount == 1 {
            return .toolCall(
                try ToolCall.encoding(
                    name: "memory.remember",
                    version: "1",
                    input: MemoryRememberInput(
                        content: "The user prefers concise technical answers.",
                        kind: .preference,
                        tags: ["communication"],
                        importance: 0.9
                    )
                )
            )
        }

        guard request.messages.contains(where: {
            $0.role == .tool && $0.content.contains("memory.remember")
        }) else {
            throw MemoryAgentTestError.toolResultMissing
        }
        return .final("Saved to Personal Memory.")
    }
}

private actor MemoryRecallingModel: ModelProvider {
    let expectedMemoryText: String
    private var callCount = 0

    init(expectedMemoryText: String) {
        self.expectedMemoryText = expectedMemoryText
    }

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        callCount += 1
        if callCount == 1 {
            return .toolCall(
                try ToolCall.encoding(
                    name: "memory.search",
                    version: "1",
                    input: MemorySearchInput(query: "language preference", limit: 5)
                )
            )
        }

        guard request.messages.contains(where: {
            $0.role == .tool && $0.content.localizedCaseInsensitiveContains(expectedMemoryText)
        }) else {
            throw MemoryAgentTestError.toolResultMissing
        }
        return .final("You prefer Ukrainian replies.")
    }
}

private enum MemoryAgentTestError: Error {
    case toolResultMissing
}
