import Foundation

public struct ConversationSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let messageCount: Int

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = max(0, messageCount)
    }
}
