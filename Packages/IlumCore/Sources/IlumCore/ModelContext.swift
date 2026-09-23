import Foundation

public protocol ModelContextProvider: Sendable {
    func context(for query: String) async throws -> GroundedContext?
}

public struct KnowledgeModelContextProvider: ModelContextProvider, Sendable {
    private let retriever: any KnowledgeRetriever
    private let builder: GroundedContextBuilder

    public init(retriever: any KnowledgeRetriever, builder: GroundedContextBuilder = GroundedContextBuilder()) {
        self.retriever = retriever; self.builder = builder
    }

    public func context(for query: String) async throws -> GroundedContext? {
        let hits = try await retriever.search(query, maxHits: builder.configuration.maxHits)
        guard !hits.isEmpty else { return nil }
        let context = try builder.build(from: hits)
        return context.entries.isEmpty ? nil : context
    }
}
