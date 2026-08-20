import XCTest
import IlumCore
@testable import IlumMacSupport

final class SecurityScopedFileCatalogTests: XCTestCase {
    func testUnknownResourceFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-catalog-tests-\(UUID().uuidString)")
            .appendingPathComponent("catalog.json")
        let catalog = try SecurityScopedFileCatalog(storeURL: url)
        XCTAssertThrowsError(try catalog.descriptor(for: UserFileResourceID(rawValue: "unknown")))
    }
}
