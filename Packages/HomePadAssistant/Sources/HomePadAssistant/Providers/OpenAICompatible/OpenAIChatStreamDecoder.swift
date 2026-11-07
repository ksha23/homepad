import Foundation
import HomePadCore

/// Decodes OpenAI Chat Completions SSE chunks (`data: {...}` lines ending with `data: [DONE]`).
struct OpenAIChatStreamDecoder: ChatStreamDecoder {
    private var text = ""
    private var reasoning = ""
    private var toolCalls = ToolCallAccumulator()
    private var finishReason: String?
    private var citations: [URL] = []

    init() {}

    mutating func decode(_ event: SSEEvent) throws -> [ChatStreamEvent] {
        let data = event.data.trimmingCharacters(in: .whitespaces)
        guard data != "[DONE]", !data.isEmpty else { return [] }
        guard let chunk = try? JSONValue.parse(data) else {
            throw AssistantError.badResponse("Unreadable stream chunk.")
        }
        if chunk["error"] != nil {
            throw AssistantError.reported(in: chunk, fallback: "The provider reported an error.")
        }
        collectCitations(chunk)

        var events: [ChatStreamEvent] = []
        for choice in chunk["choices"]?.arrayValue ?? [] {
            let delta = choice["delta"] ?? choice["message"] ?? [:]
            if let content = delta["content"]?.stringValue, !content.isEmpty {
                text += content
                events.append(.textDelta(content))
            }
            if let thinking = delta["reasoning_content"]?.stringValue {
                reasoning += thinking
            }
            for call in delta["tool_calls"]?.arrayValue ?? [] {
                let function = call["function"]
                let arguments: String? = function?["arguments"].flatMap { value in
                    value.stringValue ?? value.jsonString()
                }
                let started = toolCalls.apply(
                    index: call["index"]?.intValue,
                    id: call["id"]?.stringValue,
                    name: function?["name"]?.stringValue,
                    argumentsDelta: arguments
                )
                if let started { events.append(.toolCallStarted(name: started)) }
            }
            if let reason = choice["finish_reason"]?.stringValue {
                finishReason = reason
            }
        }
        return events
    }

    mutating func finish() throws -> (ChatMessage, StopReason) {
        var message = ChatMessage.assistant(text, toolCalls: toolCalls.calls())
        message.citations = citations
        if !reasoning.isEmpty {
            message.providerState = ["reasoning_content": .string(reasoning)]
        }
        return (message, stopReason(hasToolCalls: !message.toolCalls.isEmpty))
    }

    private func stopReason(hasToolCalls: Bool) -> StopReason {
        switch finishReason {
        case "tool_calls", "function_call": .toolUse
        case "length": .maxTokens
        case "content_filter": .refusal
        case "stop", nil: hasToolCalls ? .toolUse : .endTurn
        default: hasToolCalls ? .toolUse : .other
        }
    }

    /// Perplexity returns `citations` (URL strings) or `search_results` (objects with `url`).
    private mutating func collectCitations(_ chunk: JSONValue) {
        let strings = chunk["citations"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let results = chunk["search_results"]?.arrayValue?.compactMap { $0["url"]?.stringValue } ?? []
        for string in strings + results {
            if let url = URL(string: string), !citations.contains(url) { citations.append(url) }
        }
    }
}
