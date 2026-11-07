import Foundation
import HomePadCore

/// What every HTTP provider shares: a config, a transport, and its wire
/// format's headers. Answers are a JSON POST streamed back as server-sent
/// events, and model lists are a JSON GET, both built here so the four
/// clients only add their endpoint, encoder and decoder.
protocol HTTPChatProvider: ChatProvider {
    var transport: HTTPTransport { get }
    /// Headers for every request: the API key in this wire format's field and
    /// any vendor headers. `model` is empty for the model list.
    func headers(model: String) -> [String: String]
}

extension HTTPChatProvider {
    /// POSTs `body` as JSON to `url` and decodes the streamed reply.
    func streamEvents<Decoder: ChatStreamDecoder>(
        from url: URL, body: JSONValue, model: String, decoder: Decoder.Type
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        SSEChatStream.run(.jsonPost(url, body: body, headers: headers(model: model)), transport: transport, decoder: decoder)
    }

    /// GETs a JSON document, such as the live model list.
    func getJSON(_ url: URL) async throws -> JSONValue {
        try JSONValue(data: await transport.data(for: .get(url, headers: headers(model: ""))))
    }
}
