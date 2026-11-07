import Foundation
import HomePadCore

/// Claude through the Anthropic Messages API, with SSE streaming, tool use and images.
public struct AnthropicProvider: HTTPChatProvider {
    public let config: ProviderConfig
    let transport: HTTPTransport
    private let encoder = AnthropicEncoder()

    public init(config: ProviderConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    func headers(model: String) -> [String: String] {
        encoder.headers(apiKey: config.apiKey, model: model)
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        streamEvents(from: endpoint("messages"), body: encoder.body(for: request), model: request.model, decoder: AnthropicStreamDecoder.self)
    }

    public func listModels() async throws -> [String] {
        var url = endpoint("models")
        url.append(queryItems: [URLQueryItem(name: "limit", value: "1000")])
        return (try await getJSON(url)["data"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
    }
}
