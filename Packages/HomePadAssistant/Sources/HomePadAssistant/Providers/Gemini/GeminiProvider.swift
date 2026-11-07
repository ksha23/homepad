import Foundation
import HomePadCore

/// Google Gemini through the native `generateContent` API, with SSE streaming,
/// function calling and inline image data.
public struct GeminiProvider: HTTPChatProvider {
    public let config: ProviderConfig
    let transport: HTTPTransport

    public init(config: ProviderConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    func headers(model: String) -> [String: String] {
        var headers = config.descriptor.extraHeaders
        if let key = config.apiKey { headers["x-goog-api-key"] = key }
        return headers
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        var url = endpoint("models/\(request.model):streamGenerateContent")
        url.append(queryItems: [URLQueryItem(name: "alt", value: "sse")])
        return streamEvents(from: url, body: GeminiEncoder().body(for: request), model: request.model, decoder: GeminiStreamDecoder.self)
    }

    public func listModels() async throws -> [String] {
        var url = endpoint("models")
        url.append(queryItems: [URLQueryItem(name: "pageSize", value: "1000")])
        return Self.modelIDs(in: try await getJSON(url))
    }

    /// Keeps models that can chat (`generateContent`) and strips the `models/` prefix.
    static func modelIDs(in json: JSONValue) -> [String] {
        (json["models"]?.arrayValue ?? []).compactMap { model in
            let methods = model["supportedGenerationMethods"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard methods.contains("generateContent"), let name = model["name"]?.stringValue else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
    }
}
