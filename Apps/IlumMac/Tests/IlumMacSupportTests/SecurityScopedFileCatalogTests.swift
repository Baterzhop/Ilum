import XCTest
import IlumCore
@testable import IlumMacSupport

final class SecurityScopedFileCatalogTests: XCTestCase {
    func testUnknownResourceFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-catalog-tests-\(UUID().uuidString)")
            .appendingPathComponent("catalog.json")
        let catalog = try SecurityScopedFileCatalog(storeURL: url)
        XCTAssertThrowsError(
            try catalog.descriptor(
                for: UserFileResourceID(rawValue: "unknown")
            )
        )
    }

    func testRegisteredTextFileSurvivesCatalogReopenAndRemainsReadable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-catalog-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("selected.txt")
        let expected = "Ilum secure file lifecycle"
        try Data(expected.utf8).write(to: fileURL, options: .atomic)
        let catalogURL = root.appendingPathComponent("catalog.json")

        let resourceID: UserFileResourceID
        do {
            let catalog = try SecurityScopedFileCatalog(storeURL: catalogURL)
            let descriptor = try catalog.register(url: fileURL)
            resourceID = descriptor.id
            XCTAssertEqual(descriptor.displayName, "selected.txt")
        }

        let reopened = try SecurityScopedFileCatalog(storeURL: catalogURL)
        let descriptor = try reopened.descriptor(for: resourceID)
        let read = try await reopened.readText(
            resourceID: resourceID,
            maxBytes: 1_024
        )

        XCTAssertEqual(descriptor.displayName, "selected.txt")
        XCTAssertEqual(read.descriptor.id, resourceID)
        XCTAssertEqual(read.content, expected)
        XCTAssertFalse(read.truncated)
    }
}
