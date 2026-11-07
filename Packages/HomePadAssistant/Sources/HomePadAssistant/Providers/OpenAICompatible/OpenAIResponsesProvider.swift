import Foundation

/// OpenAI Responses API client, used for OpenAI and xAI. Their newest models
/// only offer tool calling here, not on Chat Completions.
public struct OpenAIResponsesProvider: HTTPChatProvider {
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
        let body = OpenAIResponsesEncoder(quirks: config.descriptor.quirks).body(for: request)
        return streamEvents(from: endpoint("responses"), body: body, model: request.model, decoder: OpenAIResponsesStreamDecoder.self)
    }

    public func listModels() async throws -> [String] {
        OpenAICompatibleProvider.modelIDs(in: try await getJSON(endpoint("models")))
    }
}
