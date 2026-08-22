import XCTest
@testable import IlumCore

final class PendingExecutionRecoveryTests: XCTestCase {
    func testPendingPermissionSurvivesRestartAndKeepsOriginalGroundedContext() async throws {
        let databaseURL = temporaryURL("runtime.sqlite3")
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "restart-file")
        let originalContext = try groundedContext(text: "ORIGINAL_EVIDENCE")
        let changedContext = try groundedContext(text: "CHANGED_EVIDENCE")
        var pendingID: UUID?

        do {
            let store = try SQLiteConversationStore(url: databaseURL)
            let runtime = try makeRuntime(
                store: store,
                model: RecoveryInitialModel(resourceID: resourceID),
                broker: RecoveryFileBroker(resourceID: resourceID, content: "durable file content"),
                context: originalContext
            )

            let first = try await runtime.send(
                "Read the selected file using the evidence snapshot.",
                conversationID: conversationID
            )
            guard case .permissionRequired(let pending) = first else {
                return XCTFail("Expected permission request before restart")
            }
            pendingID = pending.id

            let persisted = try await store.loadPendingExecution(conversationID: conversationID)
            XCTAssertEqual(persisted?.id, pending.id)
            XCTAssertEqual(persisted?.groundedContext, originalContext)
            XCTAssertEqual(persisted?.conversation.messages.count, 1)
        }

        let reopened = try SQLiteConversationStore(url: databaseURL)
        let runtime = try makeRuntime(
            store: reopened,
            model: RecoveryContinuationModel(
                requiredEvidence: "ORIGINAL_EVIDENCE",
                forbiddenEvidence: "CHANGED_EVIDENCE"
            ),
            broker: RecoveryFileBroker(resourceID: resourceID, content: "durable file content"),
            context: changedContext
        )

        let restored = try await runtime.restorePendingPermission(conversationID: conversationID)
        XCTAssertEqual(restored?.id, pendingID)
        XCTAssertEqual(restored?.conversation.messages.count, 1)

        guard let restored else {
            return XCTFail("Expected durable pending permission after restart")
        }

        let outcome = try await runtime.approvePermission(
            pendingID: restored.id,
            duration: .once
        )
        guard case .completed(let response) = outcome else {
            return XCTFail("Expected completion after restored approval")
        }

        XCTAssertEqual(response.assistantMessage.content, "restored continuation completed")
        XCTAssertTrue(response.conversation.messages.contains(where: {
            $0.role == .tool && $0.content.contains("durable file content")
        }))
        let pendingAfterResolution = try await reopened.loadPendingExecution(conversationID: conversationID)
        XCTAssertNil(pendingAfterResolution)

        let durableConversation = try await reopened.loadConversation(id: conversationID)
        XCTAssertEqual(durableConversation?.messages.map(\.role), [.user, .tool, .assistant])
    }

    func testDenialAfterRestartKeepsOriginalGroundedContextAndClearsPending() async throws {
        let databaseURL = temporaryURL("denial-runtime.sqlite3")
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "denial-file")
        let originalContext = try groundedContext(text: "DENIAL_ORIGINAL_EVIDENCE")
        let changedContext = try groundedContext(text: "DENIAL_CHANGED_EVIDENCE")
        var pendingID: UUID?

        do {
            let store = try SQLiteConversationStore(url: databaseURL)
            let runtime = try makeRuntime(
                store: store,
                model: RecoveryInitialModel(resourceID: resourceID),
                broker: RecoveryFileBroker(resourceID: resourceID, content: "must not be read"),
                context: originalContext
            )

            let first = try await runtime.send(
                "Request the file, then continue if I deny it.",
                conversationID: conversationID
            )
            guard case .permissionRequired(let pending) = first else {
                return XCTFail("Expected permission request before restart")
            }
            pendingID = pending.id
        }

        let reopened = try SQLiteConversationStore(url: databaseURL)
        let runtime = try makeRuntime(
            store: reopened,
            model: RecoveryDenialContinuationModel(
                requiredEvidence: "DENIAL_ORIGINAL_EVIDENCE",
                forbiddenEvidence: "DENIAL_CHANGED_EVIDENCE"
            ),
            broker: RecoveryFileBroker(resourceID: resourceID, content: "must not be read"),
            context: changedContext
        )

        guard let restored = try await runtime.restorePendingPermission(conversationID: conversationID) else {
            return XCTFail("Expected durable pending permission after restart")
        }
        XCTAssertEqual(restored.id, pendingID)

        let outcome = try await runtime.denyPermission(pendingID: restored.id)
        guard case .completed(let response) = outcome else {
            return XCTFail("Expected completion after restored denial")
        }

        XCTAssertEqual(response.assistantMessage.content, "restored denial completed")
        let toolMessages = response.conversation.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)
        guard let eventData = toolMessages[0].content.data(using: .utf8) else {
            return XCTFail("Denied tool history must be valid UTF-8 JSON")
        }
        let event = try JSONDecoder().decode(ToolHistoryEvent.self, from: eventData)
        XCTAssertEqual(event.status, .denied)
        XCTAssertNil(event.data)
        XCTAssertFalse(toolMessages[0].content.contains("must not be read"))

        let pendingAfterResolution = try await reopened.loadPendingExecution(conversationID: conversationID)
        XCTAssertNil(pendingAfterResolution)
        let durableConversation = try await reopened.loadConversation(id: conversationID)
        XCTAssertEqual(durableConversation?.messages.map(\.role), [.user, .tool, .assistant])
    }

    func testRestoredApprovalUsesLivePermissionPresentation() async throws {
        let databaseURL = temporaryURL("live-permission.sqlite3")
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "live-file")
        let store = try SQLiteConversationStore(url: databaseURL)
        let conversation = Conversation(
            id: conversationID,
            title: "Live permission",
            messages: [ChatMessage(role: .user, content: "Read it")]
        )
        try await store.saveConversation(conversation)

        let call = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )
        let serializedPresentation = PermissionRequest(
            capability: .readUserFile,
            resource: .userFile(resourceID),
            reason: "FORGED SERIALIZED REASON",
            resourceDisplayName: "forged.txt",
            resourceLocationHint: "/forged/path"
        )
        let snapshot = PendingExecutionSnapshot(
            id: UUID(),
            conversationID: conversationID,
            conversation: conversation,
            call: call,
            permission: serializedPresentation,
            completedToolSteps: 0,
            groundedContext: nil
        )
        try await store.savePendingExecution(snapshot)

        let runtime = try makeRuntime(
            store: store,
            model: RecoveryInitialModel(resourceID: resourceID),
            broker: RecoveryFileBroker(resourceID: resourceID, content: "content"),
            context: try groundedContext(text: "evidence")
        )
        let restored = try await runtime.restorePendingPermission(conversationID: conversationID)

        XCTAssertEqual(restored?.permission.reason, ReadTextFileTool.descriptor.summary)
        XCTAssertEqual(restored?.permission.resourceDisplayName, "restart.txt")
        XCTAssertEqual(restored?.permission.resourceLocationHint, "/user-selected/restart.txt")
        XCTAssertNotEqual(restored?.permission.id, serializedPresentation.id)
    }

    func testTamperedPendingPermissionResourceFailsClosed() async throws {
        let databaseURL = temporaryURL("tamper.sqlite3")
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "real-file")
        let store = try SQLiteConversationStore(url: databaseURL)
        let conversation = Conversation(
            id: conversationID,
            title: "Tamper test",
            messages: [ChatMessage(role: .user, content: "Read it")]
        )
        try await store.saveConversation(conversation)

        let call = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )
        let mismatchedPermission = PermissionRequest(
            capability: .readUserFile,
            resource: .userFile(UserFileResourceID(rawValue: "different-file")),
            reason: "mismatched authority"
        )
        try await store.savePendingExecution(
            PendingExecutionSnapshot(
                id: UUID(),
                conversationID: conversationID,
                conversation: conversation,
                call: call,
                permission: mismatchedPermission,
                completedToolSteps: 0,
                groundedContext: nil
            )
        )

        let runtime = try makeRuntime(
            store: store,
            model: RecoveryInitialModel(resourceID: resourceID),
            broker: RecoveryFileBroker(resourceID: resourceID, content: "content"),
            context: try groundedContext(text: "evidence")
        )

        do {
            _ = try await runtime.restorePendingPermission(conversationID: conversationID)
            XCTFail("Mismatched durable permission identity must fail closed")
        } catch let error as AgentRuntimeError {
            guard case .invalidPendingExecution(let detail) = error else {
                return XCTFail("Unexpected runtime error: \(error)")
            }
            XCTAssertTrue(detail.contains("permission identity"))
        }
    }

    func testConversationDeletionCascadesPendingExecution() async throws {
        let databaseURL = temporaryURL("cascade.sqlite3")
        let conversationID = UUID()
        let resourceID = UserFileResourceID(rawValue: "cascade-file")
        let store = try SQLiteConversationStore(url: databaseURL)
        let runtime = try makeRuntime(
            store: store,
            model: RecoveryInitialModel(resourceID: resourceID),
            broker: RecoveryFileBroker(resourceID: resourceID, content: "content"),
            context: try groundedContext(text: "evidence")
        )

        let first = try await runtime.send("Read it", conversationID: conversationID)
        guard case .permissionRequired = first else {
            return XCTFail("Expected pending permission")
        }
        let pendingBeforeDelete = try await store.loadPendingExecution(conversationID: conversationID)
        XCTAssertNotNil(pendingBeforeDelete)

        try await store.deleteConversation(id: conversationID)
        let conversationAfterDelete = try await store.loadConversation(id: conversationID)
        let pendingAfterDelete = try await store.loadPendingExecution(conversationID: conversationID)
        XCTAssertNil(conversationAfterDelete)
        XCTAssertNil(pendingAfterDelete)
    }

    func testUnknownFutureMigrationVersionFailsClosed() throws {
        XCTAssertNoThrow(
            try SQLiteConversationStore.validateAppliedMigrationVersions([1, 2])
        )
        XCTAssertThrowsError(
            try SQLiteConversationStore.validateAppliedMigrationVersions([1, 2, 999])
        ) { error in
            guard let storeError = error as? SQLiteStoreError,
                  case .corruptData(let detail) = storeError else {
                return XCTFail("Unexpected migration error: \(error)")
            }
            XCTAssertTrue(detail.contains("unsupported newer schema"))
            XCTAssertTrue(detail.contains("999"))
        }
    }

    private func makeRuntime(
        store: SQLiteConversationStore,
        model: any ModelProvider,
        broker: RecoveryFileBroker,
        context: GroundedContext
    ) throws -> AgentRuntime {
        let registry = try ToolRegistry(tools: [AnyTool(ReadTextFileTool(broker: broker))])
        let tools = ToolRuntime(registry: registry, permissions: PermissionEngine())
        return AgentRuntime(
            store: store,
            model: model,
            toolRuntime: tools,
            contextProvider: FixedRecoveryContextProvider(context: context),
            pendingExecutionStore: store
        )
    }

    private func groundedContext(text: String) throws -> GroundedContext {
        let hit = KnowledgeHit(
            documentID: UUID(),
            sourceResourceID: UserFileResourceID(rawValue: "evidence-source"),
            displayName: "evidence.pdf",
            chunkID: UUID(),
            chunkOrdinal: 0,
            pageStart: 1,
            pageEnd: 1,
            score: 1,
            text: text
        )
        return try GroundedContextBuilder().build(from: [hit])
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-pending-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

private struct FixedRecoveryContextProvider: ModelContextProvider, Sendable {
    let context: GroundedContext
    func context(for query: String) async throws -> GroundedContext? { context }
}

private struct RecoveryInitialModel: ModelProvider, Sendable {
    let resourceID: UserFileResourceID

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        .toolCall(
            try ToolCall.encoding(
                name: "file.readText",
                version: "2",
                input: ReadTextFileInput(resourceID: resourceID)
            )
        )
    }
}

private struct RecoveryContinuationModel: ModelProvider, Sendable {
    let requiredEvidence: String
    let forbiddenEvidence: String

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        guard let context = request.groundedContext,
              context.renderedText.contains(requiredEvidence),
              !context.renderedText.contains(forbiddenEvidence) else {
            throw RecoveryTestError.groundedSnapshotChanged
        }
        guard request.messages.contains(where: { $0.role == .tool }) else {
            throw RecoveryTestError.toolResultMissing
        }
        return .final("restored continuation completed")
    }
}

private struct RecoveryDenialContinuationModel: ModelProvider, Sendable {
    let requiredEvidence: String
    let forbiddenEvidence: String

    func respond(to request: ModelRequest) async throws -> ModelTurn {
        guard let context = request.groundedContext,
              context.renderedText.contains(requiredEvidence),
              !context.renderedText.contains(forbiddenEvidence) else {
            throw RecoveryTestError.groundedSnapshotChanged
        }
        guard let toolMessage = request.messages.last(where: { $0.role == .tool }),
              let data = toolMessage.content.data(using: .utf8),
              let event = try? JSONDecoder().decode(ToolHistoryEvent.self, from: data),
              event.status == .denied else {
            throw RecoveryTestError.toolDenialMissing
        }
        return .final("restored denial completed")
    }
}

private struct RecoveryFileBroker: UserFileAccessBroker, Sendable {
    let resourceID: UserFileResourceID
    let content: String

    func descriptor(for id: UserFileResourceID) throws -> UserFileDescriptor {
        guard id == resourceID else { throw UserFileAccessError.unknownResource(id) }
        return UserFileDescriptor(
            id: id,
            displayName: "restart.txt",
            locationHint: "/user-selected/restart.txt"
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

private enum RecoveryTestError: Error {
    case groundedSnapshotChanged
    case toolResultMissing
    case toolDenialMissing
}
