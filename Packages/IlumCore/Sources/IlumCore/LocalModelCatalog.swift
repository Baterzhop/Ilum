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
    case capabilitiesUnavailable
    case server(status: Int, body: String)

    public var description: String {
        switch self {
        case .capabilitiesUnavailable:
            return "Ollama model capabilities could not be verified. Refresh the list, update Ollama, or set ILUM_MODEL explicitly."
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

    /// The runtime always advertises tools, so automatic selection and the
    /// picker require both completion and tool support. Probe at most three
    /// metadata requests concurrently, only on startup or explicit refresh.
    public func toolCapableModels() async throws -> [LocalModelDescriptor] {
        let candidates = Self.chatCandidates(from: try await models())
        var verified: [LocalModelDescriptor] = []
        var probeFailures = 0
        for start in stride(from: 0, to: candidates.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(candidates[start..<min(start + 3, candidates.count)])
            let results = try await withThrowingTaskGroup(of: (LocalModelDescriptor, Bool?).self) { group in
                for model in batch {
                    group.addTask {
                        do { return (model, try await supportsTools(model.name)) }
                        catch {
                            if error is CancellationError || Task.isCancelled { throw CancellationError() }
                            return (model, nil)
                        }
                    }
                }
                var values: [(LocalModelDescriptor, Bool?)] = []
                for try await value in group { values.append(value) }
                return values
            }
            for (model, supported) in results {
                if supported == true { verified.append(model) }
                if supported == nil { probeFailures += 1 }
            }
        }
        if verified.isEmpty && probeFailures > 0 { throw LocalModelCatalogError.capabilitiesUnavailable }
        return Self.chatCandidates(from: verified)
    }

    private func supportsTools(_ model: String) async throws -> Bool {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw LocalModelCatalogError.invalidResponse }
        parts.path = "/api/show"
        guard let url = parts.url else { throw LocalModelCatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": model])
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode),
              let metadata = try? JSONDecoder().decode(CapabilitiesResponse.self, from: response.data) else {
            throw LocalModelCatalogError.capabilitiesUnavailable
        }
        return metadata.capabilities.contains("completion") && metadata.capabilities.contains("tools")
    }

    /// Prefer a smaller known download size for interactive use. File size is
    /// a selection heuristic, not a RAM requirement or a measured speed claim.
    public static func preferredChatModel(from models: [LocalModelDescriptor]) -> LocalModelDescriptor? {
        chatCandidates(from: models).first
    }

    public static func chatCandidates(from models: [LocalModelDescriptor]) -> [LocalModelDescriptor] {
        let sorted = models
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !looksLikeEmbeddingModel($0.name) }
            .sorted { lhs, rhs in
                let leftSize = lhs.sizeBytes.flatMap { $0 > 0 ? $0 : nil }
                let rightSize = rhs.sizeBytes.flatMap { $0 > 0 ? $0 : nil }
                if let leftSize, let rightSize, leftSize != rightSize { return leftSize < rightSize }
                if (leftSize != nil) != (rightSize != nil) { return leftSize != nil }
                let lhsScore = preferenceScore(lhs.name)
                let rhsScore = preferenceScore(rhs.name)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if lhs.name.lowercased() != rhs.name.lowercased() { return lhs.name.lowercased() < rhs.name.lowercased() }
                return lhs.name < rhs.name
            }
        var seen: Set<String> = []
        return sorted.filter { seen.insert($0.name).inserted }
    }

    /// An explicit environment setting wins even if discovery cannot see it.
    /// A saved selection is used only while that model remains installed.
    public static func selectChatModel(
        from models: [LocalModelDescriptor], configuredName: String? = nil, savedName: String? = nil
    ) -> LocalModelSelection? {
        if let configuredName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines), !configuredName.isEmpty {
            return LocalModelSelection(name: configuredName, source: .configured)
        }
        let candidates = chatCandidates(from: models)
        if let savedName, candidates.contains(where: { $0.name == savedName }) {
            return LocalModelSelection(name: savedName, source: .saved)
        }
        return candidates.first.map { LocalModelSelection(name: $0.name, source: .automatic) }
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

public struct LocalModelSelection: Equatable, Sendable {
    public enum Source: String, Sendable { case configured, saved, automatic }
    public let name: String
    public let source: Source
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

private struct CapabilitiesResponse: Decodable { let capabilities: [String] }
