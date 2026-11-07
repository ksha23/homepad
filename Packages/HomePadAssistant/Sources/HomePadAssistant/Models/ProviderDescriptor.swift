import Foundation

/// The HTTP dialect a provider speaks. Many vendors share the OpenAI one.
public enum WireFormat: String, Codable, Sendable {
    /// Apple Foundation Models on device. No network.
    case appleOnDevice
    /// OpenAI Chat Completions with SSE streaming. Used by most vendors.
    case openAIChat
    /// OpenAI Responses API. OpenAI and xAI only support tools on newer models here.
    case openAIResponses
    /// Anthropic Messages API.
    case anthropic
    /// Google Gemini `streamGenerateContent`.
    case gemini
}

/// Small per-vendor differences inside the OpenAI-compatible format.
public enum ProviderQuirk: String, Codable, Sendable {
    /// Assistant turns carry `reasoning_content` that must be echoed back during
    /// a tool loop (DeepSeek thinking mode).
    case echoReasoningContent
    /// The vendor rejects the `tools` field, so never send it (Perplexity Sonar).
    case noTools
    /// Ask the Responses API for encrypted reasoning so tool loops work with `store: false`.
    case encryptedReasoning
}

/// Static facts about one AI provider preset. User choices (key, base URL,
/// model) live in `ProviderSettings` and the keychain.
public struct ProviderDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// One line for the provider list, for example "GPT models from OpenAI".
    public let summary: String
    public let systemImage: String
    public let wireFormat: WireFormat
    public let defaultBaseURL: URL?
    public let defaultModel: String
    /// Shown in the model picker before the live list loads.
    public let suggestedModels: [String]
    public let requiresAPIKey: Bool
    /// Local servers (Ollama, LM Studio) and gateways let the user change the address.
    public let allowsCustomBaseURL: Bool
    public let supportsImages: Bool
    public let supportsTools: Bool
    /// Where to create a key.
    public let keyURL: URL?
    public let extraHeaders: [String: String]
    public let quirks: Set<ProviderQuirk>

    public init(
        id: String, displayName: String, summary: String, systemImage: String, wireFormat: WireFormat,
        defaultBaseURL: URL? = nil, defaultModel: String, suggestedModels: [String] = [],
        requiresAPIKey: Bool = true, allowsCustomBaseURL: Bool = false, supportsImages: Bool = true,
        supportsTools: Bool = true, keyURL: URL? = nil,
        extraHeaders: [String: String] = [:], quirks: Set<ProviderQuirk> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.systemImage = systemImage
        self.wireFormat = wireFormat
        self.defaultBaseURL = defaultBaseURL
        self.defaultModel = defaultModel
        self.suggestedModels = suggestedModels.isEmpty ? [defaultModel] : suggestedModels
        self.requiresAPIKey = requiresAPIKey
        self.allowsCustomBaseURL = allowsCustomBaseURL
        self.supportsImages = supportsImages
        self.supportsTools = supportsTools
        self.keyURL = keyURL
        self.extraHeaders = extraHeaders
        self.quirks = quirks
    }

    /// Keychain account holding this provider's API key.
    public var keychainAccount: String { "assistant.\(id)" }
}

/// Everything needed to call one provider: its preset plus the user's choices.
public struct ProviderConfig: Sendable {
    public var descriptor: ProviderDescriptor
    public var baseURL: URL
    public var apiKey: String?
    public var model: String

    public init(descriptor: ProviderDescriptor, baseURL: URL? = nil, apiKey: String? = nil, model: String? = nil) {
        self.descriptor = descriptor
        self.baseURL = baseURL ?? descriptor.defaultBaseURL ?? URL(string: "about:blank")!
        self.apiKey = apiKey
        self.model = (model?.isEmpty == false ? model : nil) ?? descriptor.defaultModel
    }
}

extension ProviderConfig {
    /// `Authorization: Bearer` plus the preset's extra headers, used by OpenAI-style APIs.
    var bearerHeaders: [String: String] {
        var headers = descriptor.extraHeaders
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        return headers
    }
}
