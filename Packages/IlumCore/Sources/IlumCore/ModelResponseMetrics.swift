import Foundation

/// Measurements for one completed provider call. Server durations are optional:
/// unavailable or invalid telemetry must never become a fabricated zero.
public struct ModelResponseMetrics: Equatable, Sendable {
    public let requestSeconds: Double
    public let firstTextSeconds: Double?
    public let serverTotalSeconds: Double?
    public let loadSeconds: Double?
    public let promptSeconds: Double?
    public let generationSeconds: Double?
    public let promptTokens: Int?
    public let generatedTokens: Int?

    public init(requestSeconds: Double, firstTextSeconds: Double? = nil,
                serverTotalSeconds: Double? = nil, loadSeconds: Double? = nil,
                promptSeconds: Double? = nil, generationSeconds: Double? = nil,
                promptTokens: Int? = nil, generatedTokens: Int? = nil) {
        self.requestSeconds = Self.nonnegative(requestSeconds) ?? 0
        self.firstTextSeconds = Self.nonnegative(firstTextSeconds)
        self.serverTotalSeconds = Self.nonnegative(serverTotalSeconds)
        self.loadSeconds = Self.nonnegative(loadSeconds)
        self.promptSeconds = Self.nonnegative(promptSeconds)
        self.generationSeconds = Self.nonnegative(generationSeconds)
        self.promptTokens = promptTokens.flatMap { $0 >= 0 ? $0 : nil }
        self.generatedTokens = generatedTokens.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// Includes any reasoning/tool tokens counted by the model server.
    public var generatedTokensPerSecond: Double? {
        guard let generatedTokens, let generationSeconds, generationSeconds > 0 else { return nil }
        let rate = Double(generatedTokens) / generationSeconds
        return rate.isFinite ? rate : nil
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

extension Duration {
    var ilumSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Decode optional Ollama telemetry separately from the answer protocol so a
/// missing/malformed metric does not discard an otherwise valid answer.
struct OllamaResponseMetrics: Decodable {
    let total: Double?
    let load: Double?
    let prompt: Double?
    let generation: Double?
    let promptTokens: Int?
    let generatedTokens: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = Self.seconds(c, .total)
        load = Self.seconds(c, .load)
        prompt = Self.seconds(c, .prompt)
        generation = Self.seconds(c, .generation)
        promptTokens = try? c.decode(Int.self, forKey: .promptTokens)
        generatedTokens = try? c.decode(Int.self, forKey: .generatedTokens)
    }

    func measured(requestSeconds: Double, firstTextSeconds: Double?) -> ModelResponseMetrics {
        ModelResponseMetrics(requestSeconds: requestSeconds, firstTextSeconds: firstTextSeconds,
                             serverTotalSeconds: total, loadSeconds: load, promptSeconds: prompt,
                             generationSeconds: generation, promptTokens: promptTokens, generatedTokens: generatedTokens)
    }

    private static func seconds(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        guard let nanoseconds = try? container.decode(Double.self, forKey: key), nanoseconds.isFinite, nanoseconds >= 0 else { return nil }
        return nanoseconds / 1e9
    }

    private enum CodingKeys: String, CodingKey {
        case total = "total_duration", load = "load_duration", prompt = "prompt_eval_duration"
        case generation = "eval_duration", promptTokens = "prompt_eval_count", generatedTokens = "eval_count"
    }
}
