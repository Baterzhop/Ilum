import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LocalModelDescriptor: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let sizeBytes: Int64?

    public init(name: String, sizeBytes: Int64? = nil) {
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

public enum LocalModelCatalogError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidResponse
    case server(status: Int, body: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "The local model catalog returned an invalid response."
        case .server(let status, let body):
            return "The local model catalog returned HTTP \(status): \(body)"
        }
    }
}

public protocol LocalModelCatalog: Sendable {
    func models() async throws -> [LocalModelDescriptor]
}

/// Reads the locally installed Ollama model catalog. This is discovery only:
/// it never downloads, installs, deletes, or changes a model.
public struct OllamaModelCatalog: LocalModelCatalog, Sendable {
    public let endpoint: URL
    private let transport: any HTTPTransport

    public init(
        endpoint: URL? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        let environment = ProcessInfo.processInfo.environment
        self.endpoint = endpoint
            ?? URL(string: environment["ILUM_OLLAMA_TAGS_URL"] ?? "http://127.0.0.1:11434/api/tags")!
        self.transport = transport
    }

    public func models() async throws -> [LocalModelDescriptor] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw LocalModelCatalogError.server(
                status: response.statusCode,
                body: String(data: response.data, encoding: .utf8) ?? "<non-UTF8 response>"
            )
        }

        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: response.data)
        } catch {
            throw LocalModelCatalogError.invalidResponse
        }

        return decoded.models.compactMap { raw in
            let value = (raw.name ?? raw.model ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return LocalModelDescriptor(name: value, sizeBytes: raw.size)
        }
    }

    /// Deterministic local chat-model selection. Embedding/reranker model names
    /// are excluded so an unattended first launch cannot accidentally send chat
    /// requests to an embedding-only model.
    public static func preferredChatModel(
        from models: [LocalModelDescriptor]
    ) -> LocalModelDescriptor? {
        models
            .filter { !looksLikeEmbeddingModel($0.name) }
            .sorted { lhs, rhs in
                let lhsScore = preferenceScore(lhs.name)
                let rhsScore = preferenceScore(rhs.name)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if (lhs.sizeBytes ?? 0) != (rhs.sizeBytes ?? 0) {
                    return (lhs.sizeBytes ?? 0) > (rhs.sizeBytes ?? 0)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .first
    }

    public static func looksLikeEmbeddingModel(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.contains("embed")
            || value.contains("embedding")
            || value.contains("nomic-embed")
            || value.contains("mxbai")
            || value.contains("bge-")
            || value.contains("rerank")
    }

    private static func preferenceScore(_ name: String) -> Int {
        let value = name.lowercased()
        var score = 0
        if value.contains("instruct") { score += 50 }
        if value.contains("chat") { score += 40 }
        if value.contains("qwen") { score += 20 }
        if value.contains("llama") { score += 18 }
        if value.contains("mistral") { score += 16 }
        if value.contains("gemma") { score += 14 }
        if value.contains("phi") { score += 10 }
        return score
    }
}

public enum UnavailableModelProviderError: Error, CustomStringConvertible, Sendable, Equatable {
    case unavailable(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): return reason
        }
    }
}

/// Keeps the desktop application usable for storage/file setup when no local
/// generation model is available. Chat attempts fail explicitly and visibly.
public struct UnavailableModelProvider: ModelProvider, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func respond(to request: ModelRequest) async throws -> ModelTurn {
        throw UnavailableModelProviderError.unavailable(reason)
    }
}

private struct ResponseBody: Decodable {
    let models: [RawModel]
}

private struct RawModel: Decodable {
    let name: String?
    let model: String?
    let size: Int64?
}
