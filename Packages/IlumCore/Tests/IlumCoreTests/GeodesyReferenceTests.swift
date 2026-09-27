import Foundation
import XCTest
@testable import IlumCore

final class GeodesyReferenceTests: XCTestCase {
    func testGRZSearchAcceptsGermanUkrainianAndTransliteration() {
        for query in ["Was ist die GRZ?", "Grundflächenzahl", "Grundflaechenzahl", "Поясни коефіцієнт забудови", "грз"] {
            XCTAssertEqual(GeodesyReferenceCatalog.search(query).first?.id, "grz", query)
        }
    }

    func testRequestedErhebungserlassAndFieldTopicsAreDiscoverable() {
        let cases = [
            "erhebungserlass nrw Vermessung": "erhe",
            "Lageplan": "lageplan", "межовий знак": "grenzzeichen",
            "калібрування": "kalibrierung", "SAPOS HEPS": "sapos",
            "перетворення координат": "transformation", "Baulasten": "baulasten"
        ]
        for (query, expected) in cases {
            XCTAssertEqual(GeodesyReferenceCatalog.search(query).first?.id, expected, query)
        }
    }

    func testEmptyUnrelatedAndLocationOnlyQueriesDoNotFabricateMatches() {
        for query in ["", "   ", "?!", "NRW Deutschland", "quantum lasagna"] {
            XCTAssertTrue(GeodesyReferenceCatalog.search(query).isEmpty, query)
        }
        XCTAssertTrue(GeodesyReferenceCatalog.search("GRZ", limit: 0).isEmpty)
    }

    func testEveryEntryHasDistinctIdentityProvenanceAndOfficialHTTPSLinks() throws {
        let entries = GeodesyReferenceCatalog.entries
        XCTAssertGreaterThanOrEqual(entries.count, 20)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        let hosts: Set<String> = [
            "recht.nrw.de", "www.gesetze-im-internet.de", "www.bezreg-koeln.nrw.de",
            "www.adv-online.de", "www.boris.nrw.de", "www.dinmedia.de",
            "www.bmv.de", "www.dipul.de", "maptool-dipul.dfs.de"
        ]
        for entry in entries {
            for text in [entry.title, entry.jurisdiction, entry.kind, entry.section, entry.summary,
                         entry.caution, entry.publisher, entry.sourceEdition, entry.reviewedOn] {
                XCTAssertFalse(text.isEmpty, entry.id)
            }
            XCTAssertNotEqual(entry.reviewedOn, entry.sourceEdition, entry.id)
            for source in [entry.sourceURL] + entry.relatedSourceURLs {
                let url = try XCTUnwrap(URL(string: source))
                XCTAssertEqual(url.scheme, "https")
                XCTAssertTrue(hosts.contains(url.host ?? ""), source)
            }
        }
    }

    func testLegalExamplesRetainScopeEditionAndApplicationLimits() throws {
        let grz = try XCTUnwrap(GeodesyReferenceCatalog.search("GRZ").first)
        XCTAssertEqual(grz.jurisdiction, "DE")
        XCTAssertEqual(grz.sourceURL, "https://www.gesetze-im-internet.de/baunvo/__19.html")
        XCTAssertTrue(grz.summary.contains("360 m², nicht zusätzlich 360 m²"))
        XCTAssertTrue(grz.caution.contains("Bebauungsplan"))
        let erhe = try XCTUnwrap(GeodesyReferenceCatalog.search("Erhebungserlass").first)
        XCTAssertEqual(erhe.jurisdiction, "DE-NW")
        XCTAssertTrue(erhe.sourceEdition.contains("Stammnorm"))
        XCTAssertFalse(erhe.relatedSourceURLs.isEmpty)
        XCTAssertTrue(GeodesyReferenceCatalog.scopeNote.contains("not all German states"))
    }

    func testSearchToolBoundsOutputAndPreservesSourcesThroughJSON() async throws {
        let tool = GeodesySearchTool()
        let query = "Kataster Vermessung BauNVO Grundstück Raumbezug"
        let broad = try await tool.execute(GeodesySearchInput(query: query, limit: Int.max))
        XCTAssertEqual(broad.entries.count, 5)
        let repeated = try await tool.execute(GeodesySearchInput(query: query, limit: 5))
        XCTAssertEqual(broad, repeated)
        let narrow = try await tool.execute(GeodesySearchInput(query: query, limit: -1))
        XCTAssertEqual(narrow.entries.count, 1)
        let normal = try await tool.execute(GeodesySearchInput(query: query))
        XCTAssertEqual(normal.entries.count, 3)
        let decoded = try JSONDecoder().decode(GeodesySearchOutput.self, from: JSONEncoder().encode(broad))
        XCTAssertEqual(decoded, broad)
        let unknown = try await tool.execute(GeodesySearchInput(query: "quantum lasagna"))
        XCTAssertTrue(unknown.entries.isEmpty)
        XCTAssertFalse(unknown.scopeNote.isEmpty)
    }

    func testReferenceToolUsesReadOnlyAppDataPermissionBoundary() async throws {
        let tool = GeodesySearchTool()
        XCTAssertEqual(GeodesySearchTool.descriptor.risk, .readOnly)
        XCTAssertEqual(GeodesySearchTool.descriptor.capability, .readAppData)
        XCTAssertEqual(try tool.resource(for: GeodesySearchInput(query: "GRZ")), .appData("geodesy-reference"))
        let registry = try ToolRegistry(tools: [AnyTool(tool)])
        let call = try ToolCall.encoding(name: "geodesy.search", version: "1", input: GeodesySearchInput(query: "GRZ"))
        let locked = ToolRuntime(registry: registry, permissions: PermissionEngine())
        guard case .permissionRequired = try await locked.execute(call) else {
            return XCTFail("Reference tool must respect the configured permission policy")
        }
        let runtime = ToolRuntime(
            registry: registry,
            permissions: PermissionEngine(automaticallyAllowedCapabilities: [.readAppData])
        )
        guard case .success(let result) = try await runtime.execute(call) else {
            return XCTFail("Read-only app reference should work under the macOS app policy")
        }
        let output = try JSONDecoder().decode(GeodesySearchOutput.self, from: JSONEncoder().encode(result.data))
        XCTAssertEqual(output.entries.first?.id, "grz")
        XCTAssertFalse(output.entries.first?.sourceEdition.isEmpty ?? true)
    }
}
