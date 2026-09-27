import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IlumCore

final class LocalModelCatalogTests: XCTestCase {
    func testCapabilityDiscoveryRejectsSmallEmbeddingAndTextOnlyModelsAndBoundsConcurrency() async throws {
        let transport = CapabilityHTTPTransport(responses: [
            "all-minilm": "{\"capabilities\":[\"embedding\"]}",
            "text-only": "{\"capabilities\":[\"completion\"]}",
            "qwen3:4b": "{\"capabilities\":[\"completion\",\"tools\"]}",
            "broken": "{}"
        ])
        let catalog = OllamaModelCatalog(endpoint: URL(string: "http://127.0.0.1:11434/api/tags")!, transport: transport)
        let models = try await catalog.toolCapableModels()
        XCTAssertEqual(models.map(\.name), ["qwen3:4b"])
        let peak = await transport.peakRequests()
        XCTAssertLessThanOrEqual(peak, 3)
        let paths = await transport.requestPaths()
        XCTAssertEqual(paths.filter { $0 == "/api/tags" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/api/show" }.count, 4)
    }

    func testMissingCapabilitiesCannotSilentlyBecomeAnAutomaticChatModel() async throws {
        let catalog = OllamaModelCatalog(transport: CapabilityHTTPTransport(responses: ["unknown": "{}"]))
        do { _ = try await catalog.toolCapableModels(); XCTFail("Must not guess capability from size") }
        catch let error as LocalModelCatalogError { XCTAssertEqual(error, .capabilitiesUnavailable) }
    }

    func testCapabilityDiscoveryCancellationPropagates() async throws {
        let catalog = OllamaModelCatalog(transport: CapabilityHTTPTransport(responses: ["test": "{}"], cancelProbe: true))
        do { _ = try await catalog.toolCapableModels(); XCTFail("Must propagate cancellation") }
        catch is CancellationError { }
    }

    func testOllamaCatalogDecodesInstalledModels() async throws {
        let transport = ModelCatalogHTTPTransport(
            statusCode: 200,
            body: """
            {"models":[
              {"name":"nomic-embed-text:latest","size":100},
              {"name":"qwen3:8b","size":200}
            ]}
            """
        )
        let catalog = OllamaModelCatalog(
            endpoint: URL(string: "http://127.0.0.1:11434/api/tags")!,
            transport: transport
        )

        let models = try await catalog.models()

        XCTAssertEqual(models.map(\.name), ["nomic-embed-text:latest", "qwen3:8b"])
        XCTAssertEqual(models.last?.sizeBytes, 200)
    }

    func testPreferredChatModelRejectsEmbeddingModels() {
        let selected = OllamaModelCatalog.preferredChatModel(from: [
            LocalModelDescriptor(name: "nomic-embed-text:latest", sizeBytes: 1_000),
            LocalModelDescriptor(name: "mxbai-embed-large:latest", sizeBytes: 2_000),
            LocalModelDescriptor(name: "qwen3:8b", sizeBytes: 500)
        ])

        XCTAssertEqual(selected?.name, "qwen3:8b")
    }

    func testPreferredChatModelIsDeterministic() {
        let first = OllamaModelCatalog.preferredChatModel(from: [
            LocalModelDescriptor(name: "gemma3:4b", sizeBytes: 4),
            LocalModelDescriptor(name: "qwen3:8b", sizeBytes: 8),
            LocalModelDescriptor(name: "llama3.2:3b", sizeBytes: 3)
        ])
        let second = OllamaModelCatalog.preferredChatModel(from: [
            LocalModelDescriptor(name: "llama3.2:3b", sizeBytes: 3),
            LocalModelDescriptor(name: "qwen3:8b", sizeBytes: 8),
            LocalModelDescriptor(name: "gemma3:4b", sizeBytes: 4)
        ])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.name, "llama3.2:3b")
    }

    func testSmallerKnownModelWinsOverFamilyAndInstructionNamePreferences() {
        let models = [
            LocalModelDescriptor(name: "qwen3:32b", sizeBytes: 20_000),
            LocalModelDescriptor(name: "qwen3:4b", sizeBytes: 2_500),
            LocalModelDescriptor(name: "custom-instruct:70b", sizeBytes: 40_000),
            LocalModelDescriptor(name: "llama3.2:3b", sizeBytes: 2_000)
        ]
        XCTAssertEqual(OllamaModelCatalog.preferredChatModel(from: models)?.name, "llama3.2:3b")
        XCTAssertEqual(OllamaModelCatalog.preferredChatModel(from: Array(models.prefix(2)))?.name, "qwen3:4b")
    }

    func testUnknownZeroAndNegativeSizesAreNotTreatedAsTinyModels() {
        let candidates = OllamaModelCatalog.chatCandidates(from: [
            .init(name: "qwen3:unknown"), .init(name: "qwen3:zero", sizeBytes: 0),
            .init(name: "qwen3:negative", sizeBytes: -1), .init(name: "gemma3:4b", sizeBytes: 4_000)
        ])
        XCTAssertEqual(candidates.first?.name, "gemma3:4b")
        XCTAssertEqual(candidates.count, 4)
    }

    func testCandidateListDeduplicatesNamesAndSkipsBlankAndEmbeddingEntries() {
        let candidates = OllamaModelCatalog.chatCandidates(from: [
            .init(name: "qwen3:4b", sizeBytes: 5), .init(name: "qwen3:4b", sizeBytes: 5),
            .init(name: " ", sizeBytes: 1), .init(name: "nomic-embed-text", sizeBytes: 1)
        ])
        XCTAssertEqual(candidates.map(\.name), ["qwen3:4b"])
    }

    func testConfiguredAndSavedSelectionsTakePriorityOverAutomaticChoice() {
        let models: [LocalModelDescriptor] = [.init(name: "small", sizeBytes: 2), .init(name: "large", sizeBytes: 8)]
        let configured = OllamaModelCatalog.selectChatModel(from: models, configuredName: " custom-remote ", savedName: "large")
        XCTAssertEqual(configured?.name, "custom-remote")
        XCTAssertEqual(configured?.source, .configured)
        let saved = OllamaModelCatalog.selectChatModel(from: models, configuredName: "  ", savedName: "large")
        XCTAssertEqual(saved?.name, "large")
        XCTAssertEqual(saved?.source, .saved)
        let missing = OllamaModelCatalog.selectChatModel(from: models, savedName: "removed-model")
        XCTAssertEqual(missing?.name, "small")
        XCTAssertEqual(missing?.source, .automatic)
        XCTAssertNil(OllamaModelCatalog.selectChatModel(from: [], savedName: "removed-model"))
        XCTAssertEqual(OllamaModelCatalog.selectChatModel(from: [], configuredName: "explicit")?.name, "explicit")
    }

    func testEmbeddingOnlyCatalogHasNoChatCandidate() {
        let selected = OllamaModelCatalog.preferredChatModel(from: [
            LocalModelDescriptor(name: "nomic-embed-text"),
            LocalModelDescriptor(name: "bge-m3")
        ])
        XCTAssertNil(selected)
    }

    func testUnavailableProviderFailsExplicitly() async throws {
        let provider = UnavailableModelProvider(reason: "Local model unavailable")
        do {
            _ = try await provider.respond(
                to: ModelRequest(messages: [ChatMessage(role: .user, content: "hello")])
            )
            XCTFail("Unavailable provider must never fabricate a fallback response")
        } catch let error as UnavailableModelProviderError {
            XCTAssertEqual(error, .unavailable("Local model unavailable"))
        }
    }
}

private actor ModelCatalogHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private let body: String

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        HTTPTransportResponse(statusCode: statusCode, data: Data(body.utf8))
    }
}

private actor CapabilityHTTPTransport: HTTPTransport {
    let responses: [String: String]
    let cancelProbe: Bool
    var paths: [String] = []
    var active = 0
    var peak = 0
    init(responses: [String: String], cancelProbe: Bool = false) { self.responses = responses; self.cancelProbe = cancelProbe }
    func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        let path = request.url?.path ?? ""
        paths.append(path)
        if path == "/api/tags" {
            let models = responses.keys.sorted().enumerated().map { ["name": $0.element, "size": ($0.offset + 1) * 100] as [String: Any] }
            return HTTPTransportResponse(statusCode: 200, data: try JSONSerialization.data(withJSONObject: ["models": models]))
        }
        if cancelProbe { throw CancellationError() }
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        return HTTPTransportResponse(statusCode: 200, data: Data((responses[body["model"] ?? ""] ?? "{}").utf8))
    }
    func peakRequests() -> Int { peak }
    func requestPaths() -> [String] { paths }
}
