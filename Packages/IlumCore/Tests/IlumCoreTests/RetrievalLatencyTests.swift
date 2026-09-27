import Foundation
import XCTest
@testable import IlumCore

final class RetrievalLatencyTests: XCTestCase {
    func testEmptyAndDifferentModelIndexesNeverRequestEmbeddings() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vectors = SQLiteVectorIndex(databaseURL: root.appendingPathComponent("vectors.sqlite3"))
        let embeddings = CountingEmbeddings()
        let retriever = HybridKnowledgeRetriever(
            sparse: LatencySparseRetriever(), vectors: vectors, embeddings: embeddings
        )

        let empty = try await retriever.search("hello", maxHits: 5)
        XCTAssertTrue(empty.isEmpty)
        var calls = await embeddings.callCount()
        XCTAssertEqual(calls, 0)

        let otherRecord = record(modelID: "another-model")
        try await vectors.replace(documentID: otherRecord.document.id, records: [otherRecord])
        _ = try await retriever.search("hello again", maxHits: 5)
        calls = await embeddings.callCount()
        XCTAssertEqual(calls, 0)
        let mode = await retriever.retrievalMode()
        XCTAssertEqual(mode, .sparse)
        let issue = await retriever.denseIssue()
        XCTAssertNil(issue)
    }

    func testIndexingAndDeletionChangeAvailabilityWithoutRestart() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("vectors.sqlite3")
        let vectors = SQLiteVectorIndex(databaseURL: url)
        let embeddings = CountingEmbeddings()
        let retriever = HybridKnowledgeRetriever(
            sparse: LatencySparseRetriever(), vectors: vectors, embeddings: embeddings
        )

        _ = try await retriever.search("hello", maxHits: 5)
        let added = record()
        try await vectors.replace(documentID: added.document.id, records: [added])
        let reopened = SQLiteVectorIndex(databaseURL: url)
        let exists = try await reopened.hasVectors(modelID: "test-model")
        XCTAssertTrue(exists)

        // Sparse has no matches: semantic-only hits must still be retrieved.
        let hits = try await retriever.search("semantic query", maxHits: 5)
        XCTAssertEqual(hits.map(\.chunkID), [added.chunk.id])
        let mode = await retriever.retrievalMode()
        XCTAssertEqual(mode, .hybrid)
        try await vectors.removeDocument(id: added.document.id)
        let afterDeletion = try await retriever.search("hello", maxHits: 5)
        XCTAssertTrue(afterDeletion.isEmpty)
        let calls = await embeddings.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testFailedEmbeddingIsNotRetriedDuringCooldownAndSparseRemainsUsable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vectors = SQLiteVectorIndex(databaseURL: root.appendingPathComponent("vectors.sqlite3"))
        let added = record()
        try await vectors.replace(documentID: added.document.id, records: [added])
        let sparseHit = hit(for: added)
        let embeddings = CountingEmbeddings(failures: 2)
        let retriever = HybridKnowledgeRetriever(
            sparse: LatencySparseRetriever(hits: [sparseHit]),
            vectors: vectors, embeddings: embeddings
        )

        for query in ["first question", "second question"] {
            let hits = try await retriever.search(query, maxHits: 5)
            XCTAssertEqual(hits.map(\.chunkID), [sparseHit.chunkID])
        }
        let calls = await embeddings.callCount()
        XCTAssertEqual(calls, 1)
        let mode = await retriever.retrievalMode()
        XCTAssertEqual(mode, .sparseFallback)
        let issue = await retriever.denseIssue()
        XCTAssertNotNil(issue)
    }

    func testExpiredCooldownRetriesAndClearsFallbackState() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vectors = SQLiteVectorIndex(databaseURL: root.appendingPathComponent("vectors.sqlite3"))
        let added = record()
        try await vectors.replace(documentID: added.document.id, records: [added])
        let embeddings = CountingEmbeddings(failures: 1)
        let retriever = HybridKnowledgeRetriever(
            sparse: LatencySparseRetriever(), vectors: vectors,
            embeddings: embeddings, denseFailureCooldown: .zero
        )

        _ = try await retriever.search("first question", maxHits: 5)
        let hits = try await retriever.search("second question", maxHits: 5)
        XCTAssertEqual(hits.map(\.chunkID), [added.chunk.id])
        let calls = await embeddings.callCount()
        XCTAssertEqual(calls, 2)
        let mode = await retriever.retrievalMode()
        XCTAssertEqual(mode, .hybrid)
        let issue = await retriever.denseIssue()
        XCTAssertNil(issue)
    }

    func testCancellationPropagatesInsteadOfBecomingSparseFallback() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vectors = SQLiteVectorIndex(databaseURL: root.appendingPathComponent("vectors.sqlite3"))
        let added = record()
        try await vectors.replace(documentID: added.document.id, records: [added])
        let embeddings = CountingEmbeddings(cancelFirst: true)
        let retriever = HybridKnowledgeRetriever(
            sparse: LatencySparseRetriever(), vectors: vectors, embeddings: embeddings
        )

        do {
            _ = try await retriever.search("cancel this query", maxHits: 5)
            XCTFail("Cancellation must leave the retrieval path")
        } catch is CancellationError {
            // A cancellation must not open the failure cooldown either.
        }
        let hits = try await retriever.search("next query", maxHits: 5)
        XCTAssertEqual(hits.map(\.chunkID), [added.chunk.id])
        let calls = await embeddings.callCount()
        XCTAssertEqual(calls, 2)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ilum-latency-\(UUID().uuidString)")
    }

    private func record(modelID: String = "test-model") -> DenseVectorRecord {
        let document = KnowledgeDocument(
            sourceResourceID: UserFileResourceID(rawValue: "fixture"),
            displayName: "fixture.pdf", mediaType: "application/pdf", pageCount: 1
        )
        let chunk = KnowledgeChunk(
            documentID: document.id, ordinal: 0, pageStart: 1, pageEnd: 1, text: "semantic evidence"
        )
        return DenseVectorRecord(document: document, chunk: chunk, modelID: modelID, vector: [1, 0])
    }

    private func hit(for record: DenseVectorRecord) -> KnowledgeHit {
        KnowledgeHit(
            documentID: record.document.id, sourceResourceID: record.document.sourceResourceID,
            displayName: record.document.displayName, chunkID: record.chunk.id,
            chunkOrdinal: 0, pageStart: 1, pageEnd: 1, score: 1, text: record.chunk.text
        )
    }
}

private struct LatencySparseRetriever: KnowledgeRetriever {
    var hits: [KnowledgeHit] = []
    func search(_ query: String, maxHits: Int) async throws -> [KnowledgeHit] {
        Array(hits.prefix(maxHits))
    }
}

private actor CountingEmbeddings: EmbeddingProvider {
    nonisolated let modelID = "test-model"
    private var calls = 0
    private var failures: Int
    private var cancelFirst: Bool

    init(failures: Int = 0, cancelFirst: Bool = false) {
        self.failures = failures
        self.cancelFirst = cancelFirst
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        calls += 1
        if cancelFirst { cancelFirst = false; throw CancellationError() }
        if failures > 0 { failures -= 1; throw EmbeddingError.invalidResponse }
        return texts.map { _ in [1, 0] }
    }

    func callCount() -> Int { calls }
}
