import Foundation
import HomePadCore

/// Decodes OpenAI Responses API SSE events (`response.output_text.delta`,
/// `response.output_item.added/done`, `response.completed` and friends).
struct OpenAIResponsesStreamDecoder: ChatStreamDecoder {
    private var text = ""
    /// Finished output items by output index, used when `response.completed` has no output list.
    private var doneItems: [Int: JSONValue] = [:]
    private var completedOutput: [JSONValue]?
    private var status: String?
    private var incompleteReason: String?

    init() {}

    mutating func decode(_ event: SSEEvent) throws -> [ChatStreamEvent] {
        guard let payload = try? JSONValue.parse(event.data) else { return [] }
        switch payload["type"]?.stringValue ?? event.name {
        case "response.output_text.delta", "response.refusal.delta":
            let delta = payload["delta"]?.stringValue ?? ""
            text += delta
            return delta.isEmpty ? [] : [.textDelta(delta)]
        case "response.output_item.added":
            if payload["item"]?["type"]?.stringValue == "function_call", let name = payload["item"]?["name"]?.stringValue {
                return [.toolCallStarted(name: name)]
            }
        case "response.output_item.done":
            if let index = payload["output_index"]?.intValue, let item = payload["item"] {
                doneItems[index] = item
            }
        case "response.completed", "response.incomplete":
            let response = payload["response"]
            completedOutput = response?["output"]?.arrayValue
            status = response?["status"]?.stringValue
            incompleteReason = response?["incomplete_details"]?["reason"]?.stringValue
        case "response.failed":
            let message = payload["response"]?["error"]?["message"]?.stringValue
            throw AssistantError.streamError(message ?? "The provider could not finish the response.")
        case "error":
            throw AssistantError.streamError(payload["message"]?.stringValue ?? APIErrorMessage.extract(from: payload) ?? "The provider reported an error.")
        default:
            break
        }
        return []
    }

    mutating func finish() throws -> (ChatMessage, StopReason) {
        let output = completedOutput ?? doneItems.keys.sorted().compactMap { doneItems[$0] }
        var calls: [ToolCall] = []
        var echo: [JSONValue] = []
        for item in output {
            switch item["type"]?.stringValue {
            case "function_call":
                let callID = item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "call_\(calls.count)"
                calls.append(ToolCall(id: callID, name: item["name"]?.stringValue ?? "",
                                      arguments: item["arguments"]?.stringValue ?? "{}"))
                echo.append(item)
            case "reasoning":
                // Without encrypted content a reasoning item cannot be replayed statelessly.
                if item["encrypted_content"]?.stringValue != nil { echo.append(item) }
            default:
                echo.append(item)
            }
        }
        let message = ChatMessage.assistant(text, toolCalls: calls, providerState: echo.isEmpty ? nil : .array(echo))
        return (message, stopReason(hasToolCalls: !calls.isEmpty))
    }

    private func stopReason(hasToolCalls: Bool) -> StopReason {
        if hasToolCalls { return .toolUse }
        switch (status, incompleteReason) {
        case ("incomplete", "max_output_tokens"): return .maxTokens
        case ("incomplete", "content_filter"): return .refusal
        case ("completed", _), (nil, _): return .endTurn
        default: return .other
        }
    }
}
