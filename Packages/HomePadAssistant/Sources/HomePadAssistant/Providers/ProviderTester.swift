import Foundation

/// Sends one tiny request to check a provider's key, address and model. Only
/// runs when a person taps Test in settings.
enum ProviderTester {
    static func test(_ config: ProviderConfig) async -> Result<String, Error> {
        let start = Date()
        let request = ChatRequest(
            model: config.model, system: "This is a connection test. Reply with the single word OK.",
            messages: [.user("Test")]
        )
        do {
            var reply = ""
            for try await event in ProviderFactory.make(config).stream(request) {
                if case .textDelta(let delta) = event { reply += delta }
            }
            let seconds = Date().timeIntervalSince(start)
            let shown = reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
            return .success("Works. \(config.model) replied \"\(shown)\" in \(seconds.formatted(.number.precision(.fractionLength(1)))) seconds.")
        } catch {
            return .failure(error)
        }
    }
}
