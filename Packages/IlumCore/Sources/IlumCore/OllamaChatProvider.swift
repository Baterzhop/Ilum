import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OllamaThinkingMode: String, CaseIterable, Sendable {
    case fast, thinking, modelDefault

    func value(for model: String) -> JSONValue? {
        guard self != .modelDefault else { return nil }
        let family = model.lowercased().split(separator: "/").last?.split(separator: ":").first ?? ""
        if family.hasPrefix("gpt-oss") { return .string(self == .fast ? "low" : "high") }
        return .bool(self == .thinking)
    }
}

/// Native Ollama NDJSON chat. Custom OpenAI-compatible endpoints keep their own provider.
public struct OllamaChatProvider: ModelProvider, Sendable {
    public let endpoint: URL
    public let model: String
    public let thinkingMode: OllamaThinkingMode
    private let systemPrompt: String
    private let transport: any HTTPStreamingTransport

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
        model: String,
        thinkingMode: OllamaThinkingMode = .fast,
        systemPrompt: String = "You are Ilum, a precise local personal AI assistant.",
        transport: any HTTPStreamingTransport = URLSessionStreamingTransport()
    ) {
        self.endpoint = endpoint; self.model = model; self.thinkingMode = thinkingMode
        self.systemPrompt = systemPrompt; self.transport = transport
    }

    public func respond(to request: ModelRequest) async throws -> ModelTurn {
        try await respond(to: request, onProgress: { _ in })
    }

    public func respond(to request: ModelRequest, onProgress: @escaping ModelProgressHandler) async throws -> ModelTurn {
        try Task.checkCancellation()
        try ModelMessageBuilder.validateWireNames(request.availableTools)
        let messages = try ModelMessageBuilder(systemPrompt: systemPrompt).makeAPIMessages(
            from: request.messages, availableTools: request.availableTools, groundedContext: request.groundedContext
        ).map { try OllamaMessage($0) }
        let body = OllamaRequest(
            model: model, messages: messages, stream: true,
            think: thinkingMode.value(for: model),
            tools: request.availableTools.isEmpty ? nil : request.availableTools.map(ModelMessageBuilder.makeToolDefinition),
            options: .init(numPredict: request.maxOutputTokens)
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let started = ContinuousClock.now
        let connection = transport.open(urlRequest)
        defer { connection.cancel() }
        var status: Int?
        var errorBody = Data()
        var lines = NDJSONLines()
        var accumulator = OllamaAccumulator(started: started)
        var totalBytes = 0
        do {
            for try await event in connection.events {
                try Task.checkCancellation()
                switch event {
                case .response(let code):
                    guard status == nil else { throw ModelProviderError.invalidResponse }
                    status = code
                case .data(let data):
                    guard let status else { throw ModelProviderError.invalidResponse }
                    totalBytes += data.count
                    guard totalBytes <= 8 * 1_024 * 1_024 else { throw ModelProviderError.responseTooLarge }
                    if !(200..<300).contains(status) {
                        errorBody.append(data.prefix(max(0, 4_096 - errorBody.count)))
                        continue
                    }
                    for line in try lines.append(data) {
                        if let turn = try await accumulator.consume(line, request: request, onProgress: onProgress) {
                            try Task.checkCancellation()
                            return turn
                        }
                    }
                }
            }
            try Task.checkCancellation()
            guard let status else { throw ModelProviderError.invalidResponse }
            guard (200..<300).contains(status) else {
                throw ModelProviderError.server(status: status, body: String(decoding: errorBody, as: UTF8.self))
            }
            if let last = lines.remainder(),
               let turn = try await accumulator.consume(last, request: request, onProgress: onProgress) {
                try Task.checkCancellation()
                return turn
            }
            throw ModelProviderError.incompleteStream
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}

private struct NDJSONLines {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<end])
            guard line.count <= 1_024 * 1_024 else { throw ModelProviderError.responseTooLarge }
            lines.append(line)
            buffer.removeSubrange(...end)
        }
        guard buffer.count <= 1_024 * 1_024 else { throw ModelProviderError.responseTooLarge }
        return lines
    }
    func remainder() -> Data? { buffer.isEmpty ? nil : buffer }
}

private struct OllamaAccumulator {
    var content = ""
    var thinking = ""
    var calls: [OllamaToolCall] = []
    var reportedThinking = false
    let started: ContinuousClock.Instant
    var firstTextSeconds: Double?

    mutating func consume(_ line: Data, request: ModelRequest, onProgress: ModelProgressHandler) async throws -> ModelTurn? {
        if line.allSatisfy({ $0 == 0x0D || $0 == 0x20 || $0 == 0x09 }) { return nil }
        let chunk: OllamaChunk
        do { chunk = try JSONDecoder().decode(OllamaChunk.self, from: line) }
        catch { throw ModelProviderError.invalidResponse }
        if let error = chunk.error { throw ModelProviderError.server(status: 200, body: error) }
        guard let done = chunk.done else { throw ModelProviderError.invalidResponse }
        if let message = chunk.message {
            guard message.role == nil || message.role == "assistant" else { throw ModelProviderError.invalidResponse }
            if let delta = message.thinking, !delta.isEmpty {
                thinking += delta
                if !reportedThinking { reportedThinking = true; await onProgress(.thinking) }
            }
            if let delta = message.content, !delta.isEmpty {
                content += delta
                if firstTextSeconds == nil { firstTextSeconds = started.duration(to: .now).ilumSeconds }
                await onProgress(.textDelta(delta))
            }
            calls.append(contentsOf: message.toolCalls ?? [])
            guard calls.count <= 1 else { throw ModelProviderError.multipleToolCallsUnsupported(calls.count) }
        }
        guard done else { return nil }
        guard chunk.doneReason != "length" else { throw ModelProviderError.outputLimitReached }
        guard chunk.doneReason == nil || chunk.doneReason == "stop" else { throw ModelProviderError.invalidResponse }
        let turn: ModelTurn
        if let call = calls.first {
            guard call.function.index == nil || call.function.index == 0 else { throw ModelProviderError.invalidResponse }
            guard let descriptor = request.availableTools.first(where: { $0.wireName == call.function.name }) else {
                throw ModelProviderError.unknownToolFunction(call.function.name)
            }
            guard case .object = call.function.arguments else {
                throw ModelProviderError.malformedToolArguments(tool: descriptor.registryKey)
            }
            turn = .toolCall(ToolCall(
                name: descriptor.name, version: descriptor.version,
                arguments: try JSONEncoder().encode(call.function.arguments),
                assistantContext: ToolAssistantContext(content: content, thinking: thinking)
            ))
        } else {
            let answer = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw ModelProviderError.emptyResponse }
            turn = .final(answer)
        }
        try Task.checkCancellation()
        let elapsed = started.duration(to: .now).ilumSeconds
        let server = try? JSONDecoder().decode(OllamaResponseMetrics.self, from: line)
        let metrics = server?.measured(requestSeconds: elapsed, firstTextSeconds: firstTextSeconds)
            ?? ModelResponseMetrics(requestSeconds: elapsed, firstTextSeconds: firstTextSeconds)
        await onProgress(.metrics(metrics))
        return turn
    }
}

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let think: JSONValue?
    let tools: [APIToolDefinition]?
    let options: Options
    struct Options: Encodable {
        let numPredict: Int
        enum CodingKeys: String, CodingKey { case numPredict = "num_predict" }
    }
}

private struct OllamaMessage: Encodable {
    let role: String
    let content: String
    let thinking: String?
    let toolName: String?
    let toolCalls: [OllamaToolCall]?
    init(_ message: APIRequestMessage) throws {
        role = message.role; content = message.content ?? ""; thinking = message.thinking; toolName = message.toolName
        toolCalls = try message.toolCalls?.map { call in
            let arguments = try JSONDecoder().decode(JSONValue.self, from: Data(call.function.arguments.utf8))
            return OllamaToolCall(function: .init(index: nil, name: call.function.name, arguments: arguments))
        }
    }
    enum CodingKeys: String, CodingKey { case role, content, thinking; case toolName = "tool_name"; case toolCalls = "tool_calls" }
}
private struct OllamaToolCall: Codable {
    let function: Function
    struct Function: Codable { let index: Int?; let name: String; let arguments: JSONValue }
}
private struct OllamaChunk: Decodable {
    let message: Message?
    let done: Bool?
    let doneReason: String?
    let error: String?
    struct Message: Decodable {
        let role: String?
        let content: String?
        let thinking: String?
        let toolCalls: [OllamaToolCall]?
        enum CodingKeys: String, CodingKey { case role, content, thinking; case toolCalls = "tool_calls" }
    }
    enum CodingKeys: String, CodingKey { case message, done, error; case doneReason = "done_reason" }
}
