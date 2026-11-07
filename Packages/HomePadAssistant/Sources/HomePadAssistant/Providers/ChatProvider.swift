import Foundation

/// One AI backend. Implementations are small value types that hold their
/// config and a transport. The conversation engine owns the tool loop.
public protocol ChatProvider: Sendable {
    var config: ProviderConfig { get }
    /// Streams one model turn. HTTP providers end with tool calls for the engine
    /// to run. Providers that run tools themselves use `request.executor`.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    /// Model IDs from the provider's live models endpoint.
    func listModels() async throws -> [String]
}

public extension ChatProvider {
    var descriptor: ProviderDescriptor { config.descriptor }

    /// Appends a path like `chat/completions` to the base URL, keeping any path the user typed.
    func endpoint(_ path: String) -> URL {
        config.baseURL.appending(path: path)
    }
}
