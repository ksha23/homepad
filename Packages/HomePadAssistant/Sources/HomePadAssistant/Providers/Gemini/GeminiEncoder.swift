import Foundation
import HomePadCore

/// Builds Gemini `streamGenerateContent` request bodies.
///
/// Inside a tool loop the model's parts go back verbatim through
/// `providerState`, which keeps the thought signatures Gemini 3 and later require.
struct GeminiEncoder {
    func body(for request: ChatRequest) -> JSONValue {
        var body: [String: JSONValue] = ["contents": .array(contents(for: request.messages))]
        if !request.system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": .string(request.system)]]]
        }
        if !request.tools.isEmpty {
            body["tools"] = [["functionDeclarations": .array(request.tools.map(Self.declaration))]]
        }
        if Self.usesThinkingLevel(request.model) {
            body["generationConfig"] = ["thinkingConfig": ["thinkingLevel": "low"]]
        }
        return .object(body)
    }

    /// Gemini 3 and later take `thinkingLevel` (Gemini 4 requires it). Older models reject it.
    static func usesThinkingLevel(_ model: String) -> Bool {
        let version = model.replacingOccurrences(of: "models/", with: "").dropFirst("gemini-".count)
        guard let major = version.first?.wholeNumberValue else { return false }
        return major >= 3
    }

    static func declaration(_ spec: ToolSpec) -> JSONValue {
        var declaration: [String: JSONValue] = ["name": .string(spec.name), "description": .string(spec.description)]
        if spec.hasParameters {
            declaration["parameters"] = sanitize(spec.parameters)
        }
        return .object(declaration)
    }

    /// Keeps only the OpenAPI schema subset Gemini accepts and drops empty `required` lists.
    static func sanitize(_ schema: JSONValue) -> JSONValue {
        guard let object = schema.objectValue else { return schema }
        var output: [String: JSONValue] = [:]
        for (key, value) in object where allowedSchemaKeys.contains(key) {
            switch key {
            case "properties":
                output[key] = .object((value.objectValue ?? [:]).mapValues(sanitize))
            case "items":
                output[key] = sanitize(value)
            case "anyOf":
                output[key] = .array((value.arrayValue ?? []).map(sanitize))
            case "required":
                if !(value.arrayValue ?? []).isEmpty { output[key] = value }
            default:
                output[key] = value
            }
        }
        return .object(output)
    }

    private static let allowedSchemaKeys: Set<String> = [
        "type", "format", "title", "description", "nullable", "enum", "items", "properties", "required",
        "minItems", "maxItems", "minimum", "maximum", "minLength", "maxLength", "pattern", "anyOf", "default",
    ]

    /// Gemini has `user` and `model` roles. Tool results travel as user content.
    private func contents(for messages: [ChatMessage]) -> [JSONValue] {
        ChatMessage.alternatingTurns(messages, role: { $0.role == .assistant ? "model" : "user" }, content: parts)
            .map { ["role": .string($0.role), "parts": .array($0.content)] }
    }

    private func parts(for message: ChatMessage) -> [JSONValue] {
        switch message.role {
        case .user:
            var parts: [JSONValue] = []
            if !message.text.isEmpty { parts.append(["text": .string(message.text)]) }
            for image in message.images {
                parts.append(["inlineData": ["mimeType": .string(image.mimeType), "data": .string(image.base64)]])
            }
            return parts
        case .assistant:
            if let echoed = message.echoedItems { return echoed }
            var parts: [JSONValue] = []
            if !message.text.isEmpty { parts.append(["text": .string(message.text)]) }
            for call in message.toolCalls {
                var functionCall: [String: JSONValue] = [
                    "name": .string(call.name), "args": call.argumentsObject,
                ]
                if !call.id.hasPrefix(GeminiStreamDecoder.localIDPrefix) { functionCall["id"] = .string(call.id) }
                parts.append(["functionCall": .object(functionCall)])
            }
            return parts
        case .tool:
            return message.toolResults.map { result in
                let response: JSONValue = result.isError ? ["error": .string(result.content)] : ["result": .string(result.content)]
                var functionResponse: [String: JSONValue] = ["name": .string(result.name), "response": response]
                if !result.callID.hasPrefix(GeminiStreamDecoder.localIDPrefix) { functionResponse["id"] = .string(result.callID) }
                return ["functionResponse": .object(functionResponse)]
            }
        }
    }
}
