import XCTest
@testable import IlumCore

final class ToolPermissionBindingTests: XCTestCase {
    func testOneShotGrantForCallACannotAuthorizeCallBOnSameResource() async throws {
        let resourceID = UserFileResourceID(rawValue: "shared-resource")
        let counter = ReadCounter()
        let broker = CountingFileBroker(
            resourceID: resourceID,
            content: "private content",
            counter: counter
        )
        let runtime = ToolRuntime(
            registry: try ToolRegistry(tools: [AnyTool(ReadTextFileTool(broker: broker))]),
            permissions: PermissionEngine()
        )
        let callA = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )
        let callB = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )
        XCTAssertNotEqual(callA.id, callB.id)

        let requestA = try await runtime.permissionRequest(for: callA)
        _ = await runtime.grant(
            requestA,
            duration: .once,
            callID: callA.id
        )

        let competing = try await runtime.execute(callB)
        guard case .permissionRequired(let requestB) = competing else {
            return XCTFail("Call B must not consume Call A's one-shot grant")
        }
        XCTAssertEqual(requestB.capability, requestA.capability)
        XCTAssertEqual(requestB.resource, requestA.resource)
        let readsBeforeA = await counter.value()
        XCTAssertEqual(readsBeforeA, 0)

        let approved = try await runtime.execute(callA)
        guard case .success(let success) = approved else {
            return XCTFail("Call A should execute with its own grant")
        }
        XCTAssertEqual(success.callID, callA.id)
        let readsAfterA = await counter.value()
        XCTAssertEqual(readsAfterA, 1)
    }

    func testTwoOneShotToolCallGrantsOnSameResourceDoNotReplaceEachOther() async throws {
        let resourceID = UserFileResourceID(rawValue: "shared-resource")
        let counter = ReadCounter()
        let broker = CountingFileBroker(
            resourceID: resourceID,
            content: "private content",
            counter: counter
        )
        let runtime = ToolRuntime(
            registry: try ToolRegistry(tools: [AnyTool(ReadTextFileTool(broker: broker))]),
            permissions: PermissionEngine()
        )
        let callA = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )
        let callB = try ToolCall.encoding(
            name: "file.readText",
            version: "2",
            input: ReadTextFileInput(resourceID: resourceID)
        )

        let requestA = try await runtime.permissionRequest(for: callA)
        let requestB = try await runtime.permissionRequest(for: callB)
        _ = await runtime.grant(requestA, duration: .once, callID: callA.id)
        _ = await runtime.grant(requestB, duration: .once, callID: callB.id)

        guard case .success(let first) = try await runtime.execute(callA) else {
            return XCTFail("Call A should keep its grant after Call B is also approved")
        }
        guard case .success(let second) = try await runtime.execute(callB) else {
            return XCTFail("Call B should keep its independent grant")
        }
        XCTAssertEqual(first.callID, callA.id)
        XCTAssertEqual(second.callID, callB.id)
        let totalReads = await counter.value()
        XCTAssertEqual(totalReads, 2)
    }
}

private actor ReadCounter {
    private var reads = 0

    func increment() {
        reads += 1
    }

    func value() -> Int {
        reads
    }
}

private struct CountingFileBroker: UserFileAccessBroker, Sendable {
    let resourceID: UserFileResourceID
    let content: String
    let counter: ReadCounter

    func descriptor(for id: UserFileResourceID) throws -> UserFileDescriptor {
        guard id == resourceID else {
            throw UserFileAccessError.unknownResource(id)
        }
        return UserFileDescriptor(
            id: id,
            displayName: "shared.txt",
            locationHint: "/user-selected/shared.txt"
        )
    }

    func readText(
        resourceID: UserFileResourceID,
        maxBytes: Int
    ) async throws -> UserFileTextRead {
        let descriptor = try descriptor(for: resourceID)
        await counter.increment()
        let bytes = Data(content.utf8)
        return UserFileTextRead(
            descriptor: descriptor,
            content: content,
            byteCount: min(bytes.count, maxBytes),
            truncated: bytes.count > maxBytes
        )
    }
}
