import XCTest
@testable import IlumCore

final class IlumCoreTests: XCTestCase {
    func testPermissionRequiresExplicitGrantAndOnceIsConsumed() async throws {
        let engine = PermissionEngine()
        let request = PermissionRequest(capability: .readUserFile, resource: .userFile(UserFileResourceID(rawValue: "r1")), reason: "test")
        XCTAssertFalse(await engine.authorize(request))
        _ = await engine.grant(request, duration: .once)
        XCTAssertTrue(await engine.authorize(request))
        XCTAssertFalse(await engine.authorize(request))
    }

    func testContextBudgetKeepsNewestMessageAndTrimsHistory() {
        let manager = ContextBudgetManager(policy: ContextBudgetPolicy(contextWindow: 1_024, reservedOutputTokens: 128, safetyMarginTokens: 64, fixedSystemTokens: 64, perMessageOverheadTokens: 0))
        let messages = (0..<10).map { ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: String(repeating: "x", count: 300)) }
        let pack = manager.pack(messages: messages, groundedContext: nil)
        XCTAssertFalse(pack.messages.isEmpty)
        XCTAssertEqual(pack.messages.last?.id, messages.last?.id)
        XCTAssertGreaterThan(pack.report.droppedMessageCount, 0)
    }

    func testGroundedCitationResolverFailsClosedForInventedMarker() throws {
        let hit = KnowledgeHit(
            documentID: UUID(), sourceResourceID: UserFileResourceID(rawValue: "source"), displayName: "doc.pdf",
            chunkID: UUID(), chunkOrdinal: 0, pageStart: 1, pageEnd: 1, score: 1, text: "evidence"
        )
        let context = try GroundedContextBuilder().build(from: [hit])
        XCTAssertEqual(try GroundedCitationResolver().resolve(in: "Fact [K1]", context: context).count, 1)
        XCTAssertThrowsError(try GroundedCitationResolver().resolve(in: "Invented [K2]", context: context))
    }

    func testVectorCosineSimilarity() throws {
        XCTAssertEqual(try VectorMath.cosineSimilarity([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(try VectorMath.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 0.0001)
    }

    func testReciprocalRankFusionRewardsAgreement() {
        let shared = KnowledgeHit(documentID: UUID(), sourceResourceID: UserFileResourceID(rawValue: "a"), displayName: "a", chunkID: UUID(), chunkOrdinal: 0, pageStart: 1, pageEnd: 1, score: 1, text: "shared")
        let sparseOnly = KnowledgeHit(documentID: UUID(), sourceResourceID: UserFileResourceID(rawValue: "b"), displayName: "b", chunkID: UUID(), chunkOrdinal: 0, pageStart: 1, pageEnd: 1, score: 1, text: "sparse")
        let denseOnly = KnowledgeHit(documentID: UUID(), sourceResourceID: UserFileResourceID(rawValue: "c"), displayName: "c", chunkID: UUID(), chunkOrdinal: 0, pageStart: 1, pageEnd: 1, score: 1, text: "dense")
        let fused = HybridKnowledgeRetriever.reciprocalRankFusion(sparse: [shared, sparseOnly], dense: [shared, denseOnly], limit: 3)
        XCTAssertEqual(fused.first?.chunkID, shared.chunkID)
    }

    func testSQLiteConversationSurvivesReopen() async throws {
        let url = temporaryURL("conversation.sqlite")
        let id = UUID()
        let conversation = Conversation(id: id, title: "Persistent", messages: [ChatMessage(role: .user, content: "hello")])
        do {
            let store = try SQLiteConversationStore(url: url)
            try await store.saveConversation(conversation)
        }
        let reopened = try SQLiteConversationStore(url: url)
        let loaded = try await reopened.loadConversation(id: id)
        XCTAssertEqual(loaded?.title, "Persistent")
        XCTAssertEqual(loaded?.messages.first?.content, "hello")
    }

    func testLexicalRetrievalRanksMatchingChunk() async throws {
        let store = MemoryKnowledgeStore()
        let document = KnowledgeDocument(sourceResourceID: UserFileResourceID(rawValue: "manual"), displayName: "manual.pdf", mediaType: "application/pdf", pageCount: 1)
        let chunks = [
            KnowledgeChunk(documentID: document.id, ordinal: 0, pageStart: 1, pageEnd: 1, text: "Ducati torque specification drain plug"),
            KnowledgeChunk(documentID: document.id, ordinal: 1, pageStart: 1, pageEnd: 1, text: "unrelated content")
        ]
        try await store.replaceDocument(document, chunks: chunks)
        let hits = try await LexicalKnowledgeRetriever(store: store).search("torque drain plug", maxHits: 2)
        XCTAssertEqual(hits.first?.chunkID, chunks[0].id)
    }

    private func temporaryURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ilum-tests-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent(name)
    }
}

private actor MemoryKnowledgeStore: KnowledgeStore {
    private var documents: [UUID: KnowledgeDocument] = [:]
    private var chunks: [UUID: [KnowledgeChunk]] = [:]

    func loadDocument(sourceResourceID: UserFileResourceID) async throws -> KnowledgeDocument? {
        documents.values.first { $0.sourceResourceID == sourceResourceID }
    }
    func loadChunks(documentID: UUID) async throws -> [KnowledgeChunk] { chunks[documentID] ?? [] }
    func listDocuments() async throws -> [KnowledgeDocument] { Array(documents.values) }
    func replaceDocument(_ document: KnowledgeDocument, chunks newChunks: [KnowledgeChunk]) async throws {
        documents[document.id] = document
        chunks[document.id] = newChunks
    }
}
