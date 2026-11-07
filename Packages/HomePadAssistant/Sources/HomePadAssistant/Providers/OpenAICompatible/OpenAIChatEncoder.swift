import Foundation
import HomePadCore

/// Builds OpenAI Chat Completions request bodies. Shared by every
/// OpenAI-compatible vendor, with small differences driven by `ProviderQuirk`.
struct OpenAIChatEncoder {
    let quirks: Set<ProviderQuirk>
    let supportsTools: Bool

    init(descriptor: ProviderDescriptor) {
        self.quirks = descriptor.quirks
        self.supportsTools = descriptor.supportsTools && !descriptor.quirks.contains(.noTools)
    }

    func body(for request: ChatRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "stream": true,
            "messages": .array(messages(for: request)),
        ]
        if supportsTools, !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(Self.tool))
        }
        return .object(body)
    }

    private func messages(for request: ChatRequest) -> [JSONValue] {
        var output: [JSONValue] = []
        if !request.system.isEmpty {
            output.append(["role": "system", "content": .string(request.system)])
        }
        for message in request.messages {
            switch message.role {
            case .user:
                output.append(["role": "user", "content": Self.userContent(message)])
            case .assistant:
                output.append(assistant(message))
            case .tool:
                for result in message.toolResults {
                    output.append([
                        "role": "tool",
                        "tool_call_id": .string(result.callID),
                        "content": .string(result.content),
                    ])
                }
            }
        }
        return output
    }

    /// Plain string content, or text plus `image_url` parts when images are attached.
    static func userContent(_ message: ChatMessage) -> JSONValue {
        guard !message.images.isEmpty else { return .string(message.text) }
        var parts: [JSONValue] = []
        if !message.text.isEmpty {
            parts.append(["type": "text", "text": .string(message.text)])
        }
        for image in message.images {
            parts.append(["type": "image_url", "image_url": ["url": .string(image.dataURL)]])
        }
        return .array(parts)
    }

    private func assistant(_ message: ChatMessage) -> JSONValue {
        var object: [String: JSONValue] = [
            "role": "assistant",
            "content": message.text.isEmpty && !message.toolCalls.isEmpty ? .null : .string(message.text),
        ]
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = .array(message.toolCalls.map { call in
                [
                    "id": .string(call.id),
                    "type": "function",
                    "function": ["name": .string(call.name), "arguments": .string(call.arguments)],
                ]
            })
        }
        if quirks.contains(.echoReasoningContent), let reasoning = message.providerState?["reasoning_content"] {
            object["reasoning_content"] = reasoning
        }
        return .object(object)
    }

    static func tool(_ spec: ToolSpec) -> JSONValue {
        [
            "type": "function",
            "function": [
                "name": .string(spec.name),
                "description": .string(spec.description),
                "parameters": spec.parameters,
            ],
        ]
    }
}
