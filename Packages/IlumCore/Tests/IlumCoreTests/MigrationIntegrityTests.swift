import XCTest
@testable import IlumCore

final class MigrationIntegrityTests: XCTestCase {
    func testKnownMigrationPrefixesAreAccepted() throws {
        XCTAssertNoThrow(
            try SQLiteConversationStore.validateAppliedMigrationVersions([])
        )
        XCTAssertNoThrow(
            try SQLiteConversationStore.validateAppliedMigrationVersions([1])
        )
        XCTAssertNoThrow(
            try SQLiteConversationStore.validateAppliedMigrationVersions([1, 2])
        )
    }

    func testNonContiguousMigrationLedgerFailsClosed() throws {
        XCTAssertThrowsError(
            try SQLiteConversationStore.validateAppliedMigrationVersions([2])
        ) { error in
            guard let storeError = error as? SQLiteStoreError,
                  case .corruptData(let detail) = storeError else {
                return XCTFail("Unexpected migration error: \(error)")
            }
            XCTAssertTrue(detail.contains("non-contiguous"))
            XCTAssertTrue(detail.contains("found [2]"))
            XCTAssertTrue(detail.contains("expected prefix [1]"))
        }
    }
}
