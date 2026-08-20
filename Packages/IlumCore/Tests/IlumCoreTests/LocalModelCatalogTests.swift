import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IlumCore

final class LocalModelCatalogTests: XCTestCase {
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
        XCTAssertEqual(first?.name, "qwen3:8b")
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
