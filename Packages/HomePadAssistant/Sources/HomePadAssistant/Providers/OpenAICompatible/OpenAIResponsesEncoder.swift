import Foundation
import HomePadCore

/// Builds OpenAI Responses API request bodies (also used by xAI).
///
/// Requests are stateless (`store: false`) so conversations are not kept on
/// the vendor's servers. Inside a tool loop the previous output items are sent
/// back verbatim through `providerState`, including encrypted reasoning.
struct OpenAIResponsesEncoder {
    let quirks: Set<ProviderQuirk>

    func body(for request: ChatRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "stream": true,
            "store": false,
            "input": .array(request.messages.flatMap(items)),
        ]
        if !request.system.isEmpty {
            body["instructions"] = .string(request.system)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(Self.tool))
        }
        if quirks.contains(.encryptedReasoning) {
            body["include"] = ["reasoning.encrypted_content"]
        }
        return .object(body)
    }

    /// Function tools are strict by default in this API, which would force every
    /// property to be required. HomePad tools have optional properties, so strict is off.
    static func tool(_ spec: ToolSpec) -> JSONValue {
        [
            "type": "function",
            "name": .string(spec.name),
            "description": .string(spec.description),
            "parameters": spec.parameters,
            "strict": false,
        ]
    }

    private func items(for message: ChatMessage) -> [JSONValue] {
        switch message.role {
        case .user:
            var content: [JSONValue] = []
            if !message.text.isEmpty {
                content.append(["type": "input_text", "text": .string(message.text)])
            }
            for image in message.images {
                content.append(["type": "input_image", "image_url": .string(image.dataURL)])
            }
            return [["role": "user", "content": .array(content)]]
        case .assistant:
            if let echoed = message.echoedItems { return echoed }
            var items: [JSONValue] = []
            if !message.text.isEmpty {
                items.append(["role": "assistant", "content": .string(message.text)])
            }
            for call in message.toolCalls {
                items.append([
                    "type": "function_call", "call_id": .string(call.id),
                    "name": .string(call.name), "arguments": .string(call.arguments),
                ])
            }
            return items
        case .tool:
            return message.toolResults.map { result in
                ["type": "function_call_output", "call_id": .string(result.callID), "output": .string(result.content)]
            }
        }
    }
}
