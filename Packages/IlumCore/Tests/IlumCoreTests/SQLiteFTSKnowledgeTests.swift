import Foundation
import XCTest
@testable import IlumCore

final class SQLiteFTSKnowledgeTests: XCTestCase {
    func testPersistentSparseSearchFindsStoredChunk() async throws {
        let url = temporaryURL("knowledge.sqlite3")
        let store = try SQLiteKnowledgeStore(url: url)
        let document = makeDocument(
            source: "manual-1",
            name: "service-manual.pdf"
        )
        let chunk = KnowledgeChunk(
            documentID: document.id,
            ordinal: 0,
            pageStart: 7,
            pageEnd: 7,
            text: "The rear axle torque specification is forty two newton metres."
        )

        try await store.replaceDocument(document, chunks: [chunk])
        let hits = try await store.search("axle torque specification", maxHits: 5)

        XCTAssertEqual(hits.first?.chunkID, chunk.id)
        XCTAssertEqual(hits.first?.pageStart, 7)
        XCTAssertEqual(hits.first?.displayName, "service-manual.pdf")
    }

    func testReingestionDoesNotLeaveStaleSparseText() async throws {
        let url = temporaryURL("replace.sqlite3")
        let store = try SQLiteKnowledgeStore(url: url)
        let original = makeDocument(source: "manual-2", name: "manual.pdf")
        let oldChunk = KnowledgeChunk(
            documentID: original.id,
            ordinal: 0,
            pageStart: 1,
            pageEnd: 1,
            text: "obsolete unicorn calibration procedure"
        )
        try await store.replaceDocument(original, chunks: [oldChunk])

        let replacement = KnowledgeDocument(
            id: original.id,
            sourceResourceID: original.sourceResourceID,
            displayName: original.displayName,
            mediaType: original.mediaType,
            pageCount: 1,
            createdAt: original.createdAt,
            updatedAt: Date()
        )
        let newChunk = KnowledgeChunk(
            documentID: original.id,
            ordinal: 0,
            pageStart: 1,
            pageEnd: 1,
            text: "current brake pressure calibration procedure"
        )
        try await store.replaceDocument(replacement, chunks: [newChunk])

        let stale = try await store.search("unicorn", maxHits: 5)
        let current = try await store.search("brake pressure", maxHits: 5)
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(current.first?.chunkID, newChunk.id)
    }

    func testKnowledgeDeletionSurvivesDatabaseReopen() async throws {
        let url = temporaryURL("delete.sqlite3")
        let resource = UserFileResourceID(rawValue: "private-source")
        let documentID: UUID

        do {
            let store = try SQLiteKnowledgeStore(url: url)
            let document = KnowledgeDocument(
                sourceResourceID: resource,
                displayName: "private.pdf",
                mediaType: "application/pdf",
                pageCount: 1
            )
            documentID = document.id
            try await store.replaceDocument(
                document,
                chunks: [
                    KnowledgeChunk(
                        documentID: document.id,
                        ordinal: 0,
                        pageStart: 1,
                        pageEnd: 1,
                        text: "private deletion sentinel phrase"
                    )
                ]
            )

            let beforeDeletion = try await store.search("sentinel phrase", maxHits: 5)
            XCTAssertFalse(beforeDeletion.isEmpty)

            try await store.removeDocument(sourceResourceID: resource)

            let removedDocument = try await store.loadDocument(sourceResourceID: resource)
            let removedChunks = try await store.loadChunks(documentID: documentID)
            let removedSearch = try await store.search("sentinel phrase", maxHits: 5)
            XCTAssertNil(removedDocument)
            XCTAssertTrue(removedChunks.isEmpty)
            XCTAssertTrue(removedSearch.isEmpty)
        }

        let reopened = try SQLiteKnowledgeStore(url: url)
        let reopenedDocument = try await reopened.loadDocument(sourceResourceID: resource)
        let reopenedSearch = try await reopened.search("sentinel phrase", maxHits: 5)
        XCTAssertNil(reopenedDocument)
        XCTAssertTrue(reopenedSearch.isEmpty)
    }

    private func makeDocument(source: String, name: String) -> KnowledgeDocument {
        KnowledgeDocument(
            sourceResourceID: UserFileResourceID(rawValue: source),
            displayName: name,
            mediaType: "application/pdf",
            pageCount: 10
        )
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-fts-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
