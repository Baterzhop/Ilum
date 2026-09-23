import Foundation
import IlumCore

/// One send or permission continuation. No prompts, files, or model output are
/// retained in this report. Interrupted operations are never labeled complete.
public struct GenerationPerformance: Sendable {
    public enum Outcome: String, Sendable {
        case running = "Running", completed = "Completed", awaitingPermission = "Permission required"
        case cancelled = "Cancelled", failed = "Failed"
    }
    public let model: String
    public let mode: String
    public private(set) var outcome: Outcome = .running
    public private(set) var elapsedSeconds: Double?
    public private(set) var firstTextSeconds: Double?
    public private(set) var calls: [ModelResponseMetrics] = []

    public init(model: String, mode: String) { self.model = model; self.mode = mode }

    public mutating func recordFirstText(after seconds: Double) {
        guard firstTextSeconds == nil, seconds.isFinite, seconds >= 0 else { return }
        firstTextSeconds = seconds
    }

    public mutating func record(_ metrics: ModelResponseMetrics) { calls.append(metrics) }

    public mutating func finish(_ outcome: Outcome, after seconds: Double) {
        self.outcome = outcome
        elapsedSeconds = seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    public var generatedTokensPerSecond: Double? {
        guard !calls.isEmpty, calls.allSatisfy({ $0.generatedTokens != nil && $0.generationSeconds != nil }) else { return nil }
        let duration = calls.reduce(0) { $0 + ($1.generationSeconds ?? 0) }
        guard duration > 0 else { return nil }
        let tokens = calls.reduce(0.0) { $0 + Double($1.generatedTokens ?? 0) }
        let rate = tokens / duration
        return rate.isFinite ? rate : nil
    }

    public var summary: String {
        var parts = [outcome.rawValue, "Elapsed " + Self.seconds(elapsedSeconds)]
        if let firstTextSeconds { parts.append("First text " + Self.seconds(firstTextSeconds)) }
        if let rate = generatedTokensPerSecond { parts.append(String(format: "%.1f generated tok/s", rate)) }
        return parts.joined(separator: " · ")
    }

    public var report: String {
        var lines = ["Ilum performance", "Model: \(model)", "Response mode: \(mode)", "Result: \(outcome.rawValue)",
                     "Operation elapsed: \(Self.seconds(elapsedSeconds))", "First visible text: \(Self.seconds(firstTextSeconds))",
                     "Measured completed model calls: \(calls.count)"]
        for (index, call) in calls.enumerated() {
            lines.append("")
            lines.append("Call \(index + 1)")
            lines.append("Request elapsed: \(Self.seconds(call.requestSeconds))")
            lines.append("First text from model: \(Self.seconds(call.firstTextSeconds))")
            lines.append("Ollama total: \(Self.seconds(call.serverTotalSeconds))")
            lines.append("Model loading: \(Self.seconds(call.loadSeconds))")
            lines.append("Prompt processing: \(Self.seconds(call.promptSeconds))")
            lines.append("Token generation: \(Self.seconds(call.generationSeconds))")
            lines.append("Prompt tokens: \(call.promptTokens.map(String.init) ?? "unavailable")")
            lines.append("Generated tokens: \(call.generatedTokens.map(String.init) ?? "unavailable")")
            lines.append("Generation rate: \(call.generatedTokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "unavailable")")
        }
        lines.append("")
        lines.append("Each send/approve/deny starts a separate measurement; waiting for permission is excluded.")
        lines.append("First text may be a tool preamble. Server token counts can include thinking and tool output.")
        lines.append("Server statistics cover completed model calls only; unavailable values are not zero.")
        return lines.joined(separator: "\n")
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "unavailable"
    }
}
