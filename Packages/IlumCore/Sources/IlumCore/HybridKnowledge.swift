import Foundation

public struct HybridRetrievalPolicy: Codable, Hashable, Sendable {
    public let sparseCandidates: Int
    public let denseCandidates: Int
    public let rrfK: Int
    public let sparseWeight: Double
    public let denseWeight: Double
    public let embeddingBatchSize: Int

    public init(sparseCandidates: Int = 24, denseCandidates: Int = 24, rrfK: Int = 60, sparseWeight: Double = 1, denseWeight: Double = 1, embeddingBatchSize: Int = 16) {
        self.sparseCandidates = max(1, sparseCandidates); self.denseCandidates = max(1, denseCandidates)
        self.rrfK = max(1, rrfK); self.sparseWeight = max(0, sparseWeight); self.denseWeight = max(0, denseWeight)
        self.embeddingBatchSize = max(1, embeddingBatchSize)
    }
}

public actor HybridKnowledgeRetriever: KnowledgeRetriever {
    private let sparse: any KnowledgeRetriever
    private let vectors: any DenseVectorIndex
    private let embeddings: any EmbeddingProvider
    private let policy: HybridRetrievalPolicy
    private var lastDenseIssue: String?

    public init(sparse: any KnowledgeRetriever, vectors: any DenseVectorIndex, embeddings: any EmbeddingProvider, policy: HybridRetrievalPolicy = HybridRetrievalPolicy()) {
        self.sparse = sparse; self.vectors = vectors; self.embeddings = embeddings; self.policy = policy
    }

    public func search(_ query: String, maxHits: Int) async throws -> [KnowledgeHit] {
        guard (1...50).contains(maxHits) else { throw KnowledgeRetrievalError.invalidMaxHits }
        async let sparseTask = sparse.search(query, maxHits: policy.sparseCandidates)
        var denseHits: [KnowledgeHit] = []
        do {
            guard let queryVector = try await embeddings.embed([query]).first else { throw EmbeddingError.emptyEmbedding }
            denseHits = try await vectors.search(vector: queryVector, modelID: embeddings.modelID, limit: policy.denseCandidates)
            lastDenseIssue = nil
        } catch { lastDenseIssue = String(describing: error) }
        let sparseHits = try await sparseTask
        return Self.reciprocalRankFusion(sparse: sparseHits, dense: denseHits, limit: maxHits, policy: policy)
    }

    public func denseIssue() -> String? { lastDenseIssue }

    public static func reciprocalRankFusion(sparse: [KnowledgeHit], dense: [KnowledgeHit], limit: Int, policy: HybridRetrievalPolicy = HybridRetrievalPolicy()) -> [KnowledgeHit] {
        guard limit > 0 else { return [] }
        var hitsByID: [UUID: KnowledgeHit] = [:]
        var scores: [UUID: Double] = [:]
        for (rank, hit) in sparse.enumerated() {
            hitsByID[hit.chunkID] = hitsByID[hit.chunkID] ?? hit
            scores[hit.chunkID, default: 0] += policy.sparseWeight / Double(policy.rrfK + rank + 1)
        }
        for (rank, hit) in dense.enumerated() {
            hitsByID[hit.chunkID] = hitsByID[hit.chunkID] ?? hit
            scores[hit.chunkID, default: 0] += policy.denseWeight / Double(policy.rrfK + rank + 1)
        }
        return scores.compactMap { id, score -> KnowledgeHit? in
            guard let h = hitsByID[id] else { return nil }
            return KnowledgeHit(documentID: h.documentID, sourceResourceID: h.sourceResourceID, displayName: h.displayName, chunkID: h.chunkID, chunkOrdinal: h.chunkOrdinal, pageStart: h.pageStart, pageEnd: h.pageEnd, score: score, text: h.text)
        }.sorted {
            if $0.score == $1.score { return $0.chunkID.uuidString < $1.chunkID.uuidString }
            return $0.score > $1.score
        }.prefix(limit).map { $0 }
    }
}

public struct HybridIngestionReport: Sendable {
    public let sparse: KnowledgeIngestionResult
    public let denseIndexed: Bool
    public let embeddingModel: String
    public let denseIssue: String?
}

public actor HybridKnowledgeIngestionEngine {
    private let sparseEngine: KnowledgeIngestionEngine
    private let vectors: any DenseVectorIndex
    private let embeddings: any EmbeddingProvider
    private let policy: HybridRetrievalPolicy

    public init(sparseEngine: KnowledgeIngestionEngine, vectors: any DenseVectorIndex, embeddings: any EmbeddingProvider, policy: HybridRetrievalPolicy = HybridRetrievalPolicy()) {
        self.sparseEngine = sparseEngine; self.vectors = vectors; self.embeddings = embeddings; self.policy = policy
    }

    public func ingest(resourceID: UserFileResourceID) async throws -> HybridIngestionReport {
        let sparse = try await sparseEngine.ingest(resourceID: resourceID)
        do {
            var records: [DenseVectorRecord] = []
            var start = 0
            while start < sparse.chunks.count {
                let end = min(start + policy.embeddingBatchSize, sparse.chunks.count)
                let batch = Array(sparse.chunks[start..<end])
                let batchVectors = try await embeddings.embed(batch.map(\.text))
                guard batchVectors.count == batch.count else { throw EmbeddingError.emptyEmbedding }
                for (chunk, vector) in zip(batch, batchVectors) {
                    records.append(DenseVectorRecord(document: sparse.document, chunk: chunk, modelID: embeddings.modelID, vector: vector))
                }
                start = end
            }
            try await vectors.replace(documentID: sparse.document.id, records: records)
            return HybridIngestionReport(sparse: sparse, denseIndexed: true, embeddingModel: embeddings.modelID, denseIssue: nil)
        } catch {
            try? await vectors.removeDocument(id: sparse.document.id)
            return HybridIngestionReport(sparse: sparse, denseIndexed: false, embeddingModel: embeddings.modelID, denseIssue: String(describing: error))
        }
    }
}
