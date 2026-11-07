import Foundation
import HomePadCore

/// Whether a provider can answer right now.
public enum ProviderStatus: Equatable, Sendable {
    case ready
    case off
    case needsKey
    case unavailable(String)

    public var isReady: Bool { self == .ready }

    public var label: String {
        switch self {
        case .ready: "On"
        case .off: "Off"
        case .needsKey: "Needs Key"
        case .unavailable: "Unavailable"
        }
    }
}

/// Reads and writes provider choices: switches and models in settings,
/// API keys in the keychain (account `assistant.<providerID>`).
@MainActor
struct ProviderStore {
    let settings: SettingsStore
    let keychain: KeychainStore

    func settings(for id: String) -> ProviderSettings {
        settings[AssistantSettings.providers][id] ?? ProviderSettings()
    }

    func update(_ id: String, _ change: (inout ProviderSettings) -> Void) {
        var all = settings[AssistantSettings.providers]
        var entry = all[id] ?? ProviderSettings()
        change(&entry)
        all[id] = entry
        settings[AssistantSettings.providers] = all
    }

    func apiKey(for descriptor: ProviderDescriptor) -> String? {
        keychain.string(for: descriptor.keychainAccount)
    }

    /// Saves or removes a key. Saving a key also switches the provider on.
    func setAPIKey(_ key: String?, for descriptor: ProviderDescriptor) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        keychain.set(trimmed, for: descriptor.keychainAccount)
        if trimmed?.isEmpty == false { update(descriptor.id) { $0.isEnabled = true } }
    }

    /// Apple's model is on by default where available. Cloud providers turn on
    /// when a key is saved. Local servers are off until switched on.
    func isEnabled(_ descriptor: ProviderDescriptor) -> Bool {
        if let explicit = settings(for: descriptor.id).isEnabled { return explicit }
        switch descriptor.wireFormat {
        case .appleOnDevice: return true
        default: return descriptor.requiresAPIKey && apiKey(for: descriptor) != nil
        }
    }

    func status(of descriptor: ProviderDescriptor) -> ProviderStatus {
        if descriptor.wireFormat == .appleOnDevice, let reason = AppleFoundationProvider.unavailableReason {
            return .unavailable(reason)
        }
        if descriptor.requiresAPIKey, apiKey(for: descriptor) == nil { return .needsKey }
        return isEnabled(descriptor) ? .ready : .off
    }

    /// The model the provider uses unless a person picked their own.
    func model(for descriptor: ProviderDescriptor) -> String {
        settings(for: descriptor.id).model.flatMap { $0.isEmpty ? nil : $0 } ?? descriptor.defaultModel
    }

    /// The user's address override (any HTTP provider, for proxies or local servers), else the preset's.
    func baseURL(for descriptor: ProviderDescriptor) -> URL? {
        guard descriptor.wireFormat != .appleOnDevice,
              let text = settings(for: descriptor.id).baseURL?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              let url = URL(string: text), url.scheme?.hasPrefix("http") == true
        else { return descriptor.defaultBaseURL }
        return url
    }

    func config(for descriptor: ProviderDescriptor, model: String? = nil) -> ProviderConfig {
        ProviderConfig(
            descriptor: descriptor, baseURL: baseURL(for: descriptor),
            apiKey: apiKey(for: descriptor), model: model ?? self.model(for: descriptor)
        )
    }

    var readyProviders: [ProviderDescriptor] {
        ProviderCatalog.all.filter { status(of: $0).isReady }
    }
}
