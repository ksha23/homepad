import Foundation
import HomePadCore

/// An image attached to a chat message, sent to vision-capable models.
public struct ChatImage: Codable, Hashable, Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String? = nil) {
        self.data = data
        self.mimeType = mimeType ?? Self.sniffMimeType(data)
    }

    /// Base64 without line breaks, as every provider expects.
    public var base64: String { data.base64EncodedString() }

    /// A `data:` URL for OpenAI-style `image_url` parts.
    public var dataURL: String { "data:\(mimeType);base64,\(base64)" }

    /// Detects PNG, GIF and WebP from magic bytes. Everything else is treated as JPEG.
    static func sniffMimeType(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12, bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return "image/jpeg"
    }
}

/// A function call the model asked for.
public struct ToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Raw JSON arguments exactly as the model produced them.
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// The outcome of running one tool call, sent back to the model.
public struct ToolResult: Codable, Hashable, Sendable {
    public var callID: String
    public var name: String
    public var content: String
    public var isError: Bool

    public init(callID: String, name: String, content: String, isError: Bool = false) {
        self.callID = callID
        self.name = name
        self.content = content
        self.isError = isError
    }
}

/// One provider-neutral message in a conversation. Each wire format encoder
/// turns these into its own shape.
public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        /// Results of the previous assistant message's tool calls.
        case tool
    }

    public var role: Role
    public var text: String
    public var images: [ChatImage]
    public var toolCalls: [ToolCall]
    public var toolResults: [ToolResult]
    /// Source links the provider cited (for example Perplexity search results).
    public var citations: [URL]
    /// Provider data that must go back verbatim inside one tool loop, such as
    /// Anthropic thinking blocks or Gemini thought signatures. Never persisted.
    public var providerState: JSONValue?

    public init(
        role: Role, text: String = "", images: [ChatImage] = [], toolCalls: [ToolCall] = [],
        toolResults: [ToolResult] = [], citations: [URL] = [], providerState: JSONValue? = nil
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.citations = citations
        self.providerState = providerState
    }

    public static func user(_ text: String, images: [ChatImage] = []) -> ChatMessage {
        ChatMessage(role: .user, text: text, images: images)
    }

    public static func assistant(_ text: String, toolCalls: [ToolCall] = [], providerState: JSONValue? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, toolCalls: toolCalls, providerState: providerState)
    }

    public static func toolResults(_ results: [ToolResult]) -> ChatMessage {
        ChatMessage(role: .tool, toolResults: results)
    }
}
