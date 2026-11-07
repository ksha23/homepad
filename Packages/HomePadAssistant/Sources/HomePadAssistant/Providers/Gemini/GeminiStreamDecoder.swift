import Foundation
import HomePadCore

/// Decodes Gemini `streamGenerateContent?alt=sse` events. Each `data:` line is a
/// whole `GenerateContentResponse` with new parts. Function calls arrive complete.
struct GeminiStreamDecoder: ChatStreamDecoder {
    private var text = ""
    private var parts: [JSONValue] = []
    private var calls: [ToolCall] = []
    private var finishReason: String?
    private var blocked = false

    /// Older Gemini models send calls without an id. HomePad makes one up with this
    /// prefix, and the encoder leaves such ids out when sending results back.
    static let localIDPrefix = "homepad-call-"

    init() {}

    mutating func decode(_ event: SSEEvent) throws -> [ChatStreamEvent] {
        guard let chunk = try? JSONValue.parse(event.data) else { return [] }
        if chunk["error"] != nil {
            throw AssistantError.reported(in: chunk, fallback: "Gemini reported an error.")
        }
        if chunk["promptFeedback"]?["blockReason"] != nil { blocked = true }

        var events: [ChatStreamEvent] = []
        guard let candidate = chunk["candidates"]?.arrayValue?.first else { return events }
        for part in candidate["content"]?["parts"]?.arrayValue ?? [] {
            parts.append(part)
            if let call = part["functionCall"] {
                let name = call["name"]?.stringValue ?? ""
                let id = call["id"]?.stringValue ?? "\(Self.localIDPrefix)\(calls.count)"
                calls.append(ToolCall(id: id, name: name, arguments: (call["args"] ?? [:]).jsonString()))
                events.append(.toolCallStarted(name: name))
            } else if part["thought"]?.boolValue != true, let delta = part["text"]?.stringValue, !delta.isEmpty {
                text += delta
                events.append(.textDelta(delta))
            }
        }
        if let reason = candidate["finishReason"]?.stringValue { finishReason = reason }
        return events
    }

    mutating func finish() throws -> (ChatMessage, StopReason) {
        // Parts go back unchanged, including empty text parts that only carry a thought signature.
        let message = ChatMessage.assistant(text, toolCalls: calls, providerState: parts.isEmpty ? nil : .array(parts))
        return (message, stopReason())
    }

    private func stopReason() -> StopReason {
        if blocked { return .refusal }
        if !calls.isEmpty { return .toolUse }
        switch finishReason {
        case "STOP", nil: return .endTurn
        case "MAX_TOKENS": return .maxTokens
        case "SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII": return .refusal
        default: return .other
        }
    }
}
