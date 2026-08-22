import Foundation

public protocol ConversationStore: Sendable {
    func loadConversation(id: UUID) async throws -> Conversation?
    func saveConversation(_ conversation: Conversation) async throws
}

public struct PendingExecutionSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let id: UUID
    public let conversationID: UUID
    public let conversation: Conversation
    public let call: ToolCall
    public let permission: PermissionRequest
    public let completedToolSteps: Int
    public let groundedContext: GroundedContext?
    public let createdAt: Date

    public init(
        formatVersion: Int = PendingExecutionSnapshot.currentFormatVersion,
        id: UUID,
        conversationID: UUID,
        conversation: Conversation,
        call: ToolCall,
        permission: PermissionRequest,
        completedToolSteps: Int,
        groundedContext: GroundedContext?,
        createdAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.conversationID = conversationID
        self.conversation = conversation
        self.call = call
        self.permission = permission
        self.completedToolSteps = completedToolSteps
        self.groundedContext = groundedContext
        self.createdAt = createdAt
    }

    public var approval: PendingToolApproval {
        PendingToolApproval(
            id: id,
            conversation: conversation,
            permission: permission,
            toolName: call.name,
            toolVersion: call.version,
            createdAt: createdAt
        )
    }
}

/// Durable storage for an AgentRuntime turn paused at an explicit permission gate.
/// `resolvePendingExecution` must persist the resolved conversation state and remove
/// the pending record as one storage transaction when the backing store supports it.
public protocol PendingExecutionStore: Sendable {
    func savePendingExecution(_ snapshot: PendingExecutionSnapshot) async throws
    func loadPendingExecution(conversationID: UUID) async throws -> PendingExecutionSnapshot?
    func loadPendingExecution(id: UUID) async throws -> PendingExecutionSnapshot?
    func resolvePendingExecution(id: UUID, conversation: Conversation) async throws
}

public enum StorageBootResult: Sendable {
    case ready(SQLiteConversationStore)
    case safeMode(reason: String)
}

public enum StorageBootstrap {
    public static func openSQLite(at url: URL) -> StorageBootResult {
        do { return .ready(try SQLiteConversationStore(url: url)) }
        catch { return .safeMode(reason: String(describing: error)) }
    }
}
