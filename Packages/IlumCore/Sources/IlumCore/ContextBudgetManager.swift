import Foundation

public protocol TokenEstimating: Sendable { func estimateTokens(in text: String) -> Int }

public struct HeuristicTokenEstimator: TokenEstimating, Sendable {
    public init() {}
    public func estimateTokens(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, (text.utf8.count + 2) / 3)
    }
}

public struct ContextBudgetPolicy: Codable, Hashable, Sendable {
    public let contextWindow: Int
    public let reservedOutputTokens: Int
    public let safetyMarginTokens: Int
    public let fixedSystemTokens: Int
    public let perMessageOverheadTokens: Int

    public init(
        contextWindow: Int = 8_192,
        reservedOutputTokens: Int = 1_024,
        safetyMarginTokens: Int = 512,
        fixedSystemTokens: Int = 384,
        perMessageOverheadTokens: Int = 6
    ) {
        self.contextWindow = max(1_024, contextWindow)
        self.reservedOutputTokens = max(128, reservedOutputTokens)
        self.safetyMarginTokens = max(64, safetyMarginTokens)
        self.fixedSystemTokens = max(0, fixedSystemTokens)
        self.perMessageOverheadTokens = max(0, perMessageOverheadTokens)
    }

    public static func environment() -> ContextBudgetPolicy {
        let e = ProcessInfo.processInfo.environment
        return ContextBudgetPolicy(
            contextWindow: Int(e["ILUM_CONTEXT_WINDOW"] ?? "") ?? 8_192,
            reservedOutputTokens: Int(e["ILUM_OUTPUT_TOKENS"] ?? "") ?? 1_024,
            safetyMarginTokens: Int(e["ILUM_CONTEXT_SAFETY_TOKENS"] ?? "") ?? 512
        )
    }
}

public struct ContextBudgetReport: Codable, Hashable, Sendable {
    public let contextWindow: Int
    public let inputBudgetTokens: Int
    public let estimatedInputTokens: Int
    public let historyTokens: Int
    public let knowledgeTokens: Int
    public let selectedMessageCount: Int
    public let droppedMessageCount: Int
    public let fits: Bool
}

public struct ContextBudgetPack: Sendable {
    public let messages: [ChatMessage]
    public let groundedContext: GroundedContext?
    public let report: ContextBudgetReport
}

public struct ContextBudgetManager: Sendable {
    private let estimator: any TokenEstimating
    public let policy: ContextBudgetPolicy

    public init(policy: ContextBudgetPolicy = .environment(), estimator: any TokenEstimating = HeuristicTokenEstimator()) {
        self.policy = policy; self.estimator = estimator
    }

    public func pack(messages: [ChatMessage], groundedContext: GroundedContext?) -> ContextBudgetPack {
        let inputBudget = max(0, policy.contextWindow - policy.reservedOutputTokens - policy.safetyMarginTokens - policy.fixedSystemTokens)
        let knowledgeTokens = estimator.estimateTokens(in: groundedContext?.renderedText ?? "")
        var remaining = inputBudget - knowledgeTokens
        var selectedReversed: [ChatMessage] = []
        var historyTokens = 0
        var fits = remaining >= 0

        for message in messages.reversed() {
            let cost = estimator.estimateTokens(in: message.content) + policy.perMessageOverheadTokens
            if selectedReversed.isEmpty {
                selectedReversed.append(message)
                historyTokens += cost
                remaining -= cost
                if remaining < 0 { fits = false }
                continue
            }
            guard cost <= remaining else { break }
            selectedReversed.append(message)
            historyTokens += cost
            remaining -= cost
        }

        let selected = Array(selectedReversed.reversed())
        let estimated = knowledgeTokens + historyTokens + policy.fixedSystemTokens
        fits = fits && estimated <= (inputBudget + policy.fixedSystemTokens)
        return ContextBudgetPack(
            messages: selected,
            groundedContext: groundedContext,
            report: ContextBudgetReport(
                contextWindow: policy.contextWindow,
                inputBudgetTokens: inputBudget,
                estimatedInputTokens: estimated,
                historyTokens: historyTokens,
                knowledgeTokens: knowledgeTokens,
                selectedMessageCount: selected.count,
                droppedMessageCount: max(0, messages.count - selected.count),
                fits: fits
            )
        )
    }
}
