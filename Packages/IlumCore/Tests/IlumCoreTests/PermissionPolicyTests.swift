import XCTest
@testable import IlumCore

final class PermissionPolicyTests: XCTestCase {
    func testReadOnlyCapabilityCanReceiveSessionGrant() async {
        let engine = PermissionEngine()
        let request = PermissionRequest(
            capability: .readUserFile,
            resource: .userFile(UserFileResourceID(rawValue: "file-1")),
            reason: "read selected file"
        )

        let grant = await engine.grant(request, duration: .session)
        XCTAssertEqual(grant.duration, .session)
        XCTAssertNil(grant.executionID)

        let first = await engine.authorize(request, executionID: UUID())
        let second = await engine.authorize(request, executionID: UUID())
        XCTAssertTrue(first)
        XCTAssertTrue(second)
    }

    func testWriteCapabilityCannotEscalateToSessionGrant() async {
        let engine = PermissionEngine()
        let request = PermissionRequest(
            capability: .writeAppData,
            resource: .appData("personal-memory"),
            reason: "remember stable fact"
        )
        let executionID = UUID()

        XCTAssertFalse(request.allowsSessionGrant)
        let grant = await engine.grant(
            request,
            duration: .session,
            executionID: executionID
        )
        XCTAssertEqual(grant.duration, .once)
        XCTAssertEqual(grant.executionID, executionID)

        let first = await engine.authorize(request, executionID: executionID)
        let second = await engine.authorize(request, executionID: executionID)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testOneShotGrantCannotAuthorizeDifferentExecutionOnSameResource() async {
        let engine = PermissionEngine()
        let request = PermissionRequest(
            capability: .readUserFile,
            resource: .userFile(UserFileResourceID(rawValue: "shared-file")),
            reason: "read selected file"
        )
        let approvedExecution = UUID()
        let competingExecution = UUID()

        _ = await engine.grant(
            request,
            duration: .once,
            executionID: approvedExecution
        )

        let competingAuthorized = await engine.authorize(
            request,
            executionID: competingExecution
        )
        let approvedAuthorized = await engine.authorize(
            request,
            executionID: approvedExecution
        )
        XCTAssertFalse(
            competingAuthorized,
            "A different ToolCall on the same capability/resource must not steal one-shot authority"
        )
        XCTAssertTrue(
            approvedAuthorized,
            "The failed competing authorization must not consume the approved execution's grant"
        )
    }

    func testDistinctOneShotGrantsForSameResourceCanCoexist() async {
        let engine = PermissionEngine()
        let request = PermissionRequest(
            capability: .readUserFile,
            resource: .userFile(UserFileResourceID(rawValue: "shared-file")),
            reason: "read selected file"
        )
        let firstExecution = UUID()
        let secondExecution = UUID()

        _ = await engine.grant(request, duration: .once, executionID: firstExecution)
        _ = await engine.grant(request, duration: .once, executionID: secondExecution)

        let grants = await engine.activeGrants()
        XCTAssertEqual(grants.count, 2)
        XCTAssertEqual(Set(grants.compactMap(\.executionID)), Set([firstExecution, secondExecution]))

        let firstAuthorized = await engine.authorize(request, executionID: firstExecution)
        let secondAuthorized = await engine.authorize(request, executionID: secondExecution)
        let remaining = await engine.activeGrants()
        XCTAssertTrue(firstAuthorized)
        XCTAssertTrue(secondAuthorized)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAllSideEffectingCapabilitiesAreOneShot() {
        let capabilities: [ToolCapability] = [
            .writeAppData,
            .writeUserFile,
            .externalAction,
            .systemCommand,
            .modifyCode
        ]

        for capability in capabilities {
            let request = PermissionRequest(
                capability: capability,
                resource: ResourceScope(kind: .system, identifier: capability.rawValue),
                reason: "side effect"
            )
            XCTAssertFalse(
                request.allowsSessionGrant,
                "\(capability.rawValue) must never receive a session grant"
            )
        }
    }
}
