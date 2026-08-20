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

        let first = await engine.authorize(request)
        let second = await engine.authorize(request)
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

        XCTAssertFalse(request.allowsSessionGrant)
        let grant = await engine.grant(request, duration: .session)
        XCTAssertEqual(grant.duration, .once)

        let first = await engine.authorize(request)
        let second = await engine.authorize(request)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
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
