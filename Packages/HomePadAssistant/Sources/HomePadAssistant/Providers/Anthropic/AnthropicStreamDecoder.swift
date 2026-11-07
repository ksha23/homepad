import Foundation
import HomePadCore

/// Decodes Anthropic Messages SSE (`message_start`, `content_block_*`,
/// `message_delta`, `message_stop`, `ping`, `error`).
///
/// Every content block is rebuilt so the assistant turn can be echoed back
/// unchanged inside a tool loop, which keeps thinking blocks valid.
struct AnthropicStreamDecoder: ChatStreamDecoder {
    private struct Block {
        var start: [String: JSONValue]
        var text = ""
        var thinking = ""
        var signature = ""
        var partialJSON = ""

        var type: String { start["type"]?.stringValue ?? "" }
    }

    private var blocks: [Int: Block] = [:]
    private var order: [Int] = []
    private var stopReason: String?

    init() {}

    mutating func decode(_ event: SSEEvent) throws -> [ChatStreamEvent] {
        guard let payload = try? JSONValue.parse(event.data) else { return [] }
        switch payload["type"]?.stringValue ?? event.name {
        case "content_block_start":
            guard let index = payload["index"]?.intValue, let start = payload["content_block"]?.objectValue else { return [] }
            var block = Block(start: start)
            block.text = start["text"]?.stringValue ?? ""
            block.thinking = start["thinking"]?.stringValue ?? ""
            block.signature = start["signature"]?.stringValue ?? ""
            blocks[index] = block
            order.append(index)
            if block.type == "tool_use", let name = start["name"]?.stringValue {
                return [.toolCallStarted(name: name)]
            }
            return block.text.isEmpty ? [] : [.textDelta(block.text)]
        case "content_block_delta":
            guard let index = payload["index"]?.intValue, let delta = payload["delta"] else { return [] }
            return apply(delta, to: index)
        case "message_delta":
            if let reason = payload["delta"]?["stop_reason"]?.stringValue { stopReason = reason }
            return []
        case "error":
            throw AssistantError.reported(in: payload, fallback: "Claude reported an error.")
        default:
            return []  // message_start, content_block_stop, message_stop, ping
        }
    }

    private mutating func apply(_ delta: JSONValue, to index: Int) -> [ChatStreamEvent] {
        guard var block = blocks[index] else { return [] }
        defer { blocks[index] = block }
        switch delta["type"]?.stringValue {
        case "text_delta":
            let text = delta["text"]?.stringValue ?? ""
            block.text += text
            return text.isEmpty ? [] : [.textDelta(text)]
        case "input_json_delta":
            block.partialJSON += delta["partial_json"]?.stringValue ?? ""
        case "thinking_delta":
            block.thinking += delta["thinking"]?.stringValue ?? ""
        case "signature_delta":
            block.signature += delta["signature"]?.stringValue ?? ""
        default:
            break
        }
        return []
    }

    mutating func finish() throws -> (ChatMessage, StopReason) {
        var ordered = order.compactMap { blocks[$0] }
        // After a server-side fallback, only text from before the last fallback
        // marker may be sent back. Thinking and tool calls from the declined attempt are dropped.
        if let boundary = ordered.lastIndex(where: { $0.type == "fallback" }) {
            let before = ordered[..<boundary].filter { $0.type == "text" }
            ordered = before + ordered[(boundary + 1)...]
        }

        var text = ""
        var calls: [ToolCall] = []
        var echo: [JSONValue] = []
        for block in ordered {
            switch block.type {
            case "text":
                text += block.text
                echo.append(["type": "text", "text": .string(block.text)])
            case "thinking":
                echo.append(["type": "thinking", "thinking": .string(block.thinking), "signature": .string(block.signature)])
            case "tool_use":
                let id = block.start["id"]?.stringValue ?? "toolu_\(calls.count)"
                let name = block.start["name"]?.stringValue ?? ""
                let raw = block.partialJSON.isEmpty ? (block.start["input"]?.jsonString() ?? "{}") : block.partialJSON
                let call = ToolCall(id: id, name: name, arguments: raw)
                calls.append(call)
                echo.append(["type": "tool_use", "id": .string(id), "name": .string(name), "input": call.argumentsObject])
            case "fallback":
                continue
            default:
                echo.append(.object(block.start))  // redacted_thinking and other opaque blocks
            }
        }
        let message = ChatMessage.assistant(text, toolCalls: calls, providerState: .array(echo))
        return (message, mapStopReason())
    }

    private func mapStopReason() -> StopReason {
        switch stopReason {
        case "end_turn", "stop_sequence": .endTurn
        case "tool_use": .toolUse
        case "max_tokens", "model_context_window_exceeded": .maxTokens
        case "refusal": .refusal
        default: .other
        }
    }
}
