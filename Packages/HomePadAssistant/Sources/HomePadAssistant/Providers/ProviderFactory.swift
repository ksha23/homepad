import Foundation

/// Builds the right client for a provider's wire format.
public enum ProviderFactory {
    public static func make(_ config: ProviderConfig, transport: HTTPTransport = URLSessionTransport()) -> any ChatProvider {
        switch config.descriptor.wireFormat {
        case .appleOnDevice: AppleFoundationProvider(config: config)
        case .openAIChat: OpenAICompatibleProvider(config: config, transport: transport)
        case .openAIResponses: OpenAIResponsesProvider(config: config, transport: transport)
        case .anthropic: AnthropicProvider(config: config, transport: transport)
        case .gemini: GeminiProvider(config: config, transport: transport)
        }
    }
}
