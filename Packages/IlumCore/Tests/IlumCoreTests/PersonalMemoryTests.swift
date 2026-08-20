import XCTest
@testable import IlumCore

final class PersonalMemoryTests: XCTestCase {
    func testPersonalMemoryPersistsAndDeduplicatesNormalizedContent() async throws {
        let url = temporaryURL("memory.sqlite3")
        let firstID: UUID

        do {
            let store = try SQLitePersonalMemoryStore(url: url)
            let first = try await store.remember(
                content: "Prefers concise technical answers",
                kind: .preference,
                tags: ["communication"],
                importance: 0.8
            )
            let duplicate = try await store.remember(
                content: "  prefers   concise technical answers  ",
                kind: .preference,
                tags: ["style"],
                importance: 0.9
            )
            XCTAssertEqual(first.id, duplicate.id)
            firstID = first.id
        }

        let reopened = try SQLitePersonalMemoryStore(url: url)
        let results = try await reopened.search("concise technical", limit: 5)
        XCTAssertEqual(results.first?.id, firstID)
        XCTAssertEqual(results.first?.importance, 0.9, accuracy: 0.0001)
        XCTAssertEqual(results.first?.tags, ["style"])
    }

    func testMemoryReadCanBeAutoAllowedButWriteStillRequiresApproval() async throws {
        let store = try SQLitePersonalMemoryStore(url: temporaryURL("tools.sqlite3"))
        let permissions = PermissionEngine(automaticallyAllowedCapabilities: [.readAppData])
        let registry = try ToolRegistry(tools: [
            AnyTool(MemorySearchTool(store: store)),
            AnyTool(MemoryRememberTool(store: store))
        ])
        let runtime = ToolRuntime(registry: registry, permissions: permissions)

        let searchCall = try ToolCall.encoding(
            name: "memory.search",
            version: "1",
            input: MemorySearchInput(query: "anything")
        )
        let searchOutcome = try await runtime.execute(searchCall)
        guard case .success = searchOutcome else {
            return XCTFail("readAppData should be allowed by the configured local policy")
        }

        let rememberCall = try ToolCall.encoding(
            name: "memory.remember",
            version: "1",
            input: MemoryRememberInput(content: "A durable preference", kind: .preference)
        )
        let pending = try await runtime.execute(rememberCall)
        guard case .permissionRequired(let request) = pending else {
            return XCTFail("Personal Memory writes must require explicit permission")
        }

        _ = await runtime.grant(request, duration: .once)
        let approved = try await runtime.execute(rememberCall)
        guard case .success = approved else {
            return XCTFail("The exact approved memory write should execute")
        }

        let results = try await store.search("durable preference", limit: 5)
        XCTAssertEqual(results.count, 1)
    }

    func testPersonalMemorySearchUsesImportanceOnlyAsSecondarySignal() async throws {
        let store = try SQLitePersonalMemoryStore(url: temporaryURL("ranking.sqlite3"))
        let exact = try await store.remember(
            content: "User wants a Porsche someday",
            kind: .goal,
            tags: ["car"],
            importance: 0.5
        )
        _ = try await store.remember(
            content: "User likes optimization puzzles",
            kind: .preference,
            tags: ["thinking"],
            importance: 1.0
        )

        let results = try await store.search("Porsche goal", limit: 5)
        XCTAssertEqual(results.first?.id, exact.id)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ilum-memory-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
