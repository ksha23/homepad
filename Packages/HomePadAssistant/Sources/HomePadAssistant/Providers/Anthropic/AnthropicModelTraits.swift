import Foundation

/// Per-model request options for Claude. The user may type any model ID, so
/// newer request fields are only sent to model families known to accept them.
enum AnthropicModelTraits {
    /// Families that accept `output_config.effort`.
    private static let effortPrefixes = [
        "claude-fable", "claude-mythos", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
        "claude-opus-4-6", "claude-opus-4-5", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5",
    ]

    /// Models that take the server-side `fallbacks: "default"` option, so a
    /// declined request is retried on the model Anthropic recommends.
    private static let defaultFallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    /// Families with a 64K or larger output limit.
    private static let largeOutputPrefixes = effortPrefixes + ["claude-sonnet-4-5", "claude-haiku-4-5"]

    static func supportsEffort(_ model: String) -> Bool {
        effortPrefixes.contains { model.hasPrefix($0) }
    }

    static func supportsDefaultFallbacks(_ model: String) -> Bool {
        defaultFallbackModels.contains(model)
    }

    /// Streaming requests can use a generous cap. Older models get a safe smaller one.
    static func maxOutputTokens(_ model: String) -> Int {
        largeOutputPrefixes.contains { model.hasPrefix($0) } ? 64_000 : 8_192
    }

    /// The beta header that gates `fallbacks: "default"`.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let apiVersion = "2023-06-01"
}
