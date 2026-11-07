import Foundation
import HomePadCore

/// Builds Anthropic Messages API request bodies and headers.
///
/// Voice answers favor latency, so effort is `low` on models that accept it.
/// Thinking is left at the model default (adaptive on current models), and
/// thinking blocks from a tool loop go back unchanged through `providerState`.
struct AnthropicEncoder {
    /// Default effort for spoken, conversational answers.
    static let effort = "low"

    func body(for request: ChatRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "max_tokens": .number(Double(AnthropicModelTraits.maxOutputTokens(request.model))),
            "stream": true,
            "messages": .array(messages(for: request.messages)),
        ]
        if !request.system.isEmpty {
            body["system"] = .string(request.system)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(Self.tool))
        }
        if AnthropicModelTraits.supportsEffort(request.model) {
            body["output_config"] = ["effort": .string(Self.effort)]
        }
        if AnthropicModelTraits.supportsDefaultFallbacks(request.model) {
            body["fallbacks"] = "default"
        }
        return .object(body)
    }

    func headers(apiKey: String?, model: String) -> [String: String] {
        var headers = ["anthropic-version": AnthropicModelTraits.apiVersion]
        if let apiKey { headers["x-api-key"] = apiKey }
        if AnthropicModelTraits.supportsDefaultFallbacks(model) {
            headers["anthropic-beta"] = AnthropicModelTraits.fallbackBeta
        }
        return headers
    }

    /// Client tools stream their input eagerly. The engine validates the JSON before running anything.
    static func tool(_ spec: ToolSpec) -> JSONValue {
        [
            "name": .string(spec.name),
            "description": .string(spec.description),
            "input_schema": spec.parameters,
            "eager_input_streaming": true,
        ]
    }

    /// Maps messages to alternating user and assistant turns, merging neighbors with the same role.
    func messages(for messages: [ChatMessage]) -> [JSONValue] {
        ChatMessage.alternatingTurns(messages, role: { $0.role == .assistant ? "assistant" : "user" }, content: content)
            .map { ["role": .string($0.role), "content": .array($0.content)] }
    }

    private func content(for message: ChatMessage) -> [JSONValue] {
        switch message.role {
        case .user:
            var blocks: [JSONValue] = message.images.map { image in
                [
                    "type": "image",
                    "source": ["type": "base64", "media_type": .string(image.mimeType), "data": .string(image.base64)],
                ]
            }
            if !message.text.isEmpty {
                blocks.append(["type": "text", "text": .string(message.text)])
            }
            return blocks
        case .assistant:
            if let echoed = message.echoedItems { return echoed }
            var blocks: [JSONValue] = []
            if !message.text.isEmpty {
                blocks.append(["type": "text", "text": .string(message.text)])
            }
            for call in message.toolCalls {
                blocks.append([
                    "type": "tool_use",
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": call.argumentsObject,
                ])
            }
            return blocks
        case .tool:
            return message.toolResults.map { result in
                var block: [String: JSONValue] = [
                    "type": "tool_result",
                    "tool_use_id": .string(result.callID),
                    "content": .string(result.content),
                ]
                if result.isError { block["is_error"] = true }
                return .object(block)
            }
        }
    }
}
