import Foundation
import HomePadCore

/// One client for every OpenAI-compatible endpoint: OpenAI, xAI, Mistral,
/// DeepSeek, Groq, Perplexity, OpenRouter, Ollama, LM Studio and custom servers.
public struct OpenAICompatibleProvider: HTTPChatProvider {
    public let config: ProviderConfig
    let transport: HTTPTransport

    public init(config: ProviderConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    func headers(model: String) -> [String: String] {
        config.bearerHeaders
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let body = OpenAIChatEncoder(descriptor: config.descriptor).body(for: request)
        return streamEvents(from: endpoint("chat/completions"), body: body, model: request.model, decoder: OpenAIChatStreamDecoder.self)
    }

    public func listModels() async throws -> [String] {
        Self.modelIDs(in: try await getJSON(endpoint("models")))
    }

    /// Reads `{"data":[{"id":...}]}`, the shape every compatible server returns,
    /// and drops speech, embedding, image and moderation models that cannot chat.
    static func modelIDs(in json: JSONValue) -> [String] {
        let items = json["data"]?.arrayValue ?? json["models"]?.arrayValue ?? []
        return items.compactMap { $0["id"]?.stringValue ?? $0["name"]?.stringValue }
            .filter { id in !nonChatMarkers.contains { id.lowercased().contains($0) } }
            .sorted()
    }

    private static let nonChatMarkers = [
        "embed", "whisper", "tts", "dall-e", "gpt-image", "moderation", "guard", "transcribe", "realtime", "orpheus",
    ]
}
