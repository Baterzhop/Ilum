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

/// Additive estimates for a provider's rendered messages, tool schemas and instructions.
public struct ModelContextCosts: Sendable {
    public let messageTokens: [Int]
    public let fixedTokens: Int
    public let knowledgeTokens: Int
    public init(messageTokens: [Int], fixedTokens: Int, knowledgeTokens: Int) {
        self.messageTokens = messageTokens
        self.fixedTokens = fixedTokens
        self.knowledgeTokens = knowledgeTokens
    }
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
        pack(messages: messages, groundedContext: groundedContext, costs: nil)
    }

    public func pack(request: ModelRequest, model: any ModelProvider) throws -> ContextBudgetPack {
        let costs = try model.contextCosts(for: request, estimator: estimator, messageOverhead: policy.perMessageOverheadTokens)
        if let costs {
            guard costs.messageTokens.count == request.messages.count,
                  costs.fixedTokens >= 0, costs.knowledgeTokens >= 0,
                  costs.messageTokens.allSatisfy({ $0 >= 0 }) else {
                throw ModelProviderError.invalidResponse
            }
        }
        return pack(messages: request.messages, groundedContext: request.groundedContext, costs: costs)
    }

    private func pack(messages: [ChatMessage], groundedContext: GroundedContext?, costs profile: ModelContextCosts?) -> ContextBudgetPack {
        let fixedTokens = max(policy.fixedSystemTokens, profile?.fixedTokens ?? 0)
        let availableInput = max(0, policy.contextWindow - policy.reservedOutputTokens - policy.safetyMarginTokens)
        let inputBudget = max(0, availableInput - fixedTokens)
        let knowledgeTokens = profile?.knowledgeTokens ?? estimator.estimateTokens(in: groundedContext?.renderedText ?? "")
        // Pin explicit system messages and keep each user turn with all of its
        // tool results/assistant messages. Never leave a tool continuation without
        // its user request, or silently drop the active request to fit a result.
        let costs = profile?.messageTokens ?? messages.map { estimator.estimateTokens(in: $0.content) + policy.perMessageOverheadTokens }
        var selectedIndices = Set<Int>()
        var turns: [[Int]] = []
        for (index, message) in messages.enumerated() {
            if message.role == .system {
                selectedIndices.insert(index)
            } else {
                if message.role == .user || turns.isEmpty { turns.append([]) }
                turns[turns.count - 1].append(index)
            }
        }
        var historyTokens = selectedIndices.reduce(0) { $0 + costs[$1] }
        var remaining = inputBudget - knowledgeTokens - historyTokens
        for (offset, turn) in turns.reversed().enumerated() {
            let cost = turn.reduce(0) { $0 + costs[$1] }
            // The active turn is mandatory; report overflow instead of truncating it.
            guard offset == 0 || cost <= remaining else { break }
            selectedIndices.formUnion(turn)
            historyTokens += cost
            remaining -= cost
        }
        let selected = messages.enumerated().compactMap { selectedIndices.contains($0.offset) ? $0.element : nil }
        var fits = remaining >= 0
        let estimated = knowledgeTokens + historyTokens + fixedTokens
        fits = fits && estimated <= availableInput
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
