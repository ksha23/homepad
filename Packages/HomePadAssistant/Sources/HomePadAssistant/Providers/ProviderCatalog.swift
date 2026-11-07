import Foundation

/// Every provider HomePad knows. Model defaults were checked against each
/// vendor's docs in October 2026. People can load the live model list once a
/// key is saved, or type any model ID.
public enum ProviderCatalog {
    public static let all: [ProviderDescriptor] = [
        apple, openAI, anthropic, gemini, xAI, meta, mistral, deepSeek, groq, perplexity, openRouter, ollama, lmStudio,
    ]

    public static func descriptor(_ id: String) -> ProviderDescriptor? {
        all.first { $0.id == id }
    }

    static let apple = ProviderDescriptor(
        id: "apple", displayName: "Apple Intelligence", summary: "On-device model. Private, free and works offline.",
        systemImage: "apple.intelligence", wireFormat: .appleOnDevice, defaultModel: "on-device",
        requiresAPIKey: false, supportsImages: AppleFoundationProvider.supportsImages
    )

    static let openAI = ProviderDescriptor(
        id: "openai", displayName: "OpenAI", summary: "GPT models from OpenAI.",
        systemImage: "circle.hexagongrid", wireFormat: .openAIResponses,
        defaultBaseURL: URL(string: "https://api.openai.com/v1"), defaultModel: "gpt-6.1-sol",
        suggestedModels: ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"],
        keyURL: URL(string: "https://platform.openai.com/api-keys"), quirks: [.encryptedReasoning]
    )

    static let anthropic = ProviderDescriptor(
        id: "anthropic", displayName: "Claude", summary: "Claude models from Anthropic.",
        systemImage: "asterisk", wireFormat: .anthropic,
        // Haiku by default: a spoken answer wants speed, and Opus thought too long
        // before every reply. Bigger models stay one pick away.
        defaultBaseURL: URL(string: "https://api.anthropic.com/v1"), defaultModel: "claude-haiku-5-5",
        suggestedModels: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"],
        keyURL: URL(string: "https://platform.claude.com/settings/keys")
    )

    static let gemini = ProviderDescriptor(
        id: "gemini", displayName: "Gemini", summary: "Gemini models from Google.",
        systemImage: "sparkle", wireFormat: .gemini,
        defaultBaseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta"), defaultModel: "gemini-3.8-flash",
        suggestedModels: ["gemini-3.8-flash", "gemini-4-argon", "gemini-3.5-flash-lite"],
        keyURL: URL(string: "https://aistudio.google.com/apikey")
    )

    static let xAI = ProviderDescriptor(
        id: "xai", displayName: "Grok", summary: "Grok models from xAI.",
        systemImage: "xmark.circle", wireFormat: .openAIResponses,
        defaultBaseURL: URL(string: "https://api.x.ai/v1"), defaultModel: "grok-4.7",
        suggestedModels: ["grok-4.7", "grok-4.3"],
        keyURL: URL(string: "https://console.x.ai")
    )

    static let meta = ProviderDescriptor(
        id: "meta", displayName: "Meta Muse", summary: "Muse Spark from Meta. Public preview, not offered in every country.",
        systemImage: "infinity", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://api.meta.ai/v1"), defaultModel: "muse-spark-1.3",
        suggestedModels: ["muse-spark-1.3", "muse-wonder-1.0"],
        keyURL: URL(string: "https://dev.meta.ai/api-keys/")
    )

    static let mistral = ProviderDescriptor(
        id: "mistral", displayName: "Mistral", summary: "Mistral models from Mistral AI.",
        systemImage: "wind", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://api.mistral.ai/v1"), defaultModel: "mistral-medium-latest",
        suggestedModels: ["mistral-medium-latest", "mistral-small-latest", "mistral-large-latest"],
        keyURL: URL(string: "https://console.mistral.ai/api-keys")
    )

    static let deepSeek = ProviderDescriptor(
        id: "deepseek", displayName: "DeepSeek", summary: "DeepSeek models. Text only.",
        systemImage: "water.waves", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://api.deepseek.com"), defaultModel: "deepseek-v4-pro",
        suggestedModels: ["deepseek-v4-pro", "deepseek-flash"], supportsImages: false,
        keyURL: URL(string: "https://platform.deepseek.com/api_keys"), quirks: [.echoReasoningContent]
    )

    static let groq = ProviderDescriptor(
        id: "groq", displayName: "Groq", summary: "Very fast open models on Groq hardware.",
        systemImage: "bolt", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://api.groq.com/openai/v1"), defaultModel: "openai/gpt-oss-120b",
        suggestedModels: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "llama-3.1-8b-instant"], supportsImages: false,
        keyURL: URL(string: "https://console.groq.com/keys")
    )

    static let perplexity = ProviderDescriptor(
        id: "perplexity", displayName: "Perplexity", summary: "Web search answers with sources. Cannot control the home.",
        systemImage: "magnifyingglass", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://api.perplexity.ai"), defaultModel: "sonar-pro",
        suggestedModels: ["sonar-pro", "sonar"], supportsImages: false, supportsTools: false,
        keyURL: URL(string: "https://www.perplexity.ai/account/api/keys"), quirks: [.noTools]
    )

    static let openRouter = ProviderDescriptor(
        id: "openrouter", displayName: "OpenRouter", summary: "One key for hundreds of models.",
        systemImage: "point.3.connected.trianglepath.dotted", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "https://openrouter.ai/api/v1"), defaultModel: "openrouter/auto",
        keyURL: URL(string: "https://openrouter.ai/settings/keys"),
        extraHeaders: ["HTTP-Referer": "https://github.com/ksha23/homepad", "X-Title": "HomePad"]
    )

    static let ollama = ProviderDescriptor(
        id: "ollama", displayName: "Ollama", summary: "Models on a computer in your home. Enter its network address.",
        systemImage: "desktopcomputer", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "http://localhost:11434/v1"), defaultModel: "llama3.2",
        requiresAPIKey: false, allowsCustomBaseURL: true
    )

    static let lmStudio = ProviderDescriptor(
        id: "lmstudio", displayName: "LM Studio", summary: "Models on a computer in your home. Enter its network address.",
        systemImage: "laptopcomputer", wireFormat: .openAIChat,
        defaultBaseURL: URL(string: "http://localhost:1234/v1"), defaultModel: "openai/gpt-oss-20b",
        requiresAPIKey: false, allowsCustomBaseURL: true
    )
}
