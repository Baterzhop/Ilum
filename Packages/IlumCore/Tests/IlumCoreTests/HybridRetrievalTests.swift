import XCTest
@testable import IlumCore

final class HybridRetrievalTests: XCTestCase {
    func testDenseFailureFallsBackToSparseRetrieval() async throws {
        let sparseHit = KnowledgeHit(
            documentID: UUID(),
            sourceResourceID: UserFileResourceID(rawValue: "source"),
            displayName: "manual.pdf",
            chunkID: UUID(),
            chunkOrdinal: 0,
            pageStart: 1,
            pageEnd: 1,
            score: 3,
            text: "sparse evidence"
        )
        let retriever = HybridKnowledgeRetriever(
            sparse: StubRetriever(hits: [sparseHit]),
            vectors: StubVectorIndex(),
            embeddings: FailingEmbeddingProvider()
        )

        let hits = try await retriever.search("query", maxHits: 5)

        XCTAssertEqual(hits.map(\.chunkID), [sparseHit.chunkID])
        let issue = await retriever.denseIssue()
        XCTAssertNotNil(issue)
    }

    func testSQLiteVectorIndexPersistsAcrossInstances() async throws {
        let url = temporaryURL("vectors.sqlite3")
        let document = KnowledgeDocument(
            sourceResourceID: UserFileResourceID(rawValue: "source"),
            displayName: "manual.pdf",
            mediaType: "application/pdf",
            pageCount: 1
        )
        let chunk = KnowledgeChunk(
            documentID: document.id,
            ordinal: 0,
            pageStart: 1,
            pageEnd: 1,
            text: "semantic evidence"
        )

        do {
            let index = SQLiteVectorIndex(databaseURL: url)
            try await index.replace(
                documentID: document.id,
                records: [
                    DenseVectorRecord(
                        document: document,
                        chunk: chunk,
                        modelID: "test-model",
                        vector: [1, 0, 0]
                    )
                ]
            )
        }

        let reopened = SQLiteVectorIndex(databaseURL: url)
        let hits = try await reopened.search(
            vector: [1, 0, 0],
            modelID: "test-model",
            limit: 3
        )

        XCTAssertEqual(hits.first?.chunkID, chunk.id)
        XCTAssertEqual(hits.first?.documentID, document.id)
        XCTAssertEqual(hits.first?.displayName, "manual.pdf")
    }

    func testHybridIngestionRemovesStaleDenseDataWhenEmbeddingFails() async throws {
        let resourceID = UserFileResourceID(rawValue: "pdf")
        let sparseStore = HybridTestKnowledgeStore()
        let sparseEngine = KnowledgeIngestionEngine(
            extractor: StubExtractor(resourceID: resourceID),
            store: sparseStore
        )
        let vectorIndex = RecordingVectorIndex()
        let engine = HybridKnowledgeIngestionEngine(
            sparseEngine: sparseEngine,
            vectors: vectorIndex,
            embeddings: FailingEmbeddingProvider()
        )

        let report = try await engine.ingest(resourceID: resourceID)

        XCTAssertFalse(report.denseIndexed)
        XCTAssertEqual(report.sparse.chunks.count, 1)
        let removed = await vectorIndex.removedDocumentIDs()
        XCTAssertEqual(removed, [report.sparse.document.id])
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-vector-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

private struct StubRetriever: KnowledgeRetriever, Sendable {
    let hits: [KnowledgeHit]
    func search(_ query: String, maxHits: Int) async throws -> [KnowledgeHit] {
        Array(hits.prefix(maxHits))
    }
}

private struct FailingEmbeddingProvider: EmbeddingProvider, Sendable {
    let modelID = "failing-model"
    func embed(_ texts: [String]) async throws -> [[Float]] {
        throw EmbeddingError.invalidResponse
    }
}

private actor StubVectorIndex: DenseVectorIndex {
    func replace(documentID: UUID, records: [DenseVectorRecord]) async throws {}
    func removeDocument(id: UUID) async throws {}
    func search(vector: [Float], modelID: String, limit: Int) async throws -> [KnowledgeHit] {
        []
    }
}

private actor RecordingVectorIndex: DenseVectorIndex {
    private var removed: [UUID] = []

    func replace(documentID: UUID, records: [DenseVectorRecord]) async throws {}

    func removeDocument(id: UUID) async throws {
        removed.append(id)
    }

    func search(vector: [Float], modelID: String, limit: Int) async throws -> [KnowledgeHit] {
        []
    }

    func removedDocumentIDs() -> [UUID] {
        removed
    }
}

private actor HybridTestKnowledgeStore: KnowledgeStore {
    private var document: KnowledgeDocument?
    private var chunks: [KnowledgeChunk] = []

    func loadDocument(sourceResourceID: UserFileResourceID) async throws -> KnowledgeDocument? {
        guard document?.sourceResourceID == sourceResourceID else { return nil }
        return document
    }

    func loadChunks(documentID: UUID) async throws -> [KnowledgeChunk] {
        guard document?.id == documentID else { return [] }
        return chunks
    }

    func listDocuments() async throws -> [KnowledgeDocument] {
        document.map { [$0] } ?? []
    }

    func replaceDocument(_ document: KnowledgeDocument, chunks: [KnowledgeChunk]) async throws {
        self.document = document
        self.chunks = chunks
    }
}

private struct StubExtractor: DocumentTextExtractor, Sendable {
    let resourceID: UserFileResourceID

    func extract(resourceID: UserFileResourceID) async throws -> ExtractedDocument {
        guard resourceID == self.resourceID else {
            throw DocumentExtractionError.invalidDocument("wrong resource")
        }
        return ExtractedDocument(
            sourceResourceID: resourceID,
            displayName: "fixture.pdf",
            mediaType: "application/pdf",
            pages: [
                ExtractedDocumentPage(
                    pageNumber: 1,
                    text: "This fixture is long enough to become one deterministic knowledge chunk for the hybrid ingestion regression test. " + String(repeating: "evidence ", count: 40)
                )
            ]
        )
    }
}
