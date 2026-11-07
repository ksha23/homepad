import Foundation
import HomePadCore

/// Where Home Assistant lives and the long-lived access token to reach it.
struct HomeAssistantConfiguration: Equatable, Sendable {
    var baseURL: URL
    var token: String

    /// An authorized request for a path such as `api/camera_proxy/camera.front`.
    func request(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url ?? baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Normalizes what people type ("homeassistant.local:8123", "http://ha/lovelace/0/")
    /// into a scheme, host and port. Returns nil for text that is not a host.
    static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}

/// Loads and saves the configuration: the URL in settings, the token in the keychain.
@MainActor
struct HomeAssistantConfigurationStore {
    var load: () -> HomeAssistantConfiguration?
    var save: (HomeAssistantConfiguration?) -> Void

    static func live(settings: SettingsStore, keychain: KeychainStore) -> HomeAssistantConfigurationStore {
        HomeAssistantConfigurationStore(
            load: {
                guard let url = HomeAssistantConfiguration.normalizedURL(from: settings[SmartHomeSettings.homeAssistantURL]),
                      let token = keychain.string(for: SmartHomeSettings.homeAssistantTokenAccount), !token.isEmpty else { return nil }
                return HomeAssistantConfiguration(baseURL: url, token: token)
            },
            save: { configuration in
                settings[SmartHomeSettings.homeAssistantURL] = configuration?.baseURL.absoluteString ?? ""
                keychain.set(configuration?.token, for: SmartHomeSettings.homeAssistantTokenAccount)
            }
        )
    }

    /// Keeps the configuration in memory, for tests and previews.
    static func inMemory(_ initial: HomeAssistantConfiguration? = nil) -> HomeAssistantConfigurationStore {
        final class Box { var value: HomeAssistantConfiguration? }
        let box = Box()
        box.value = initial
        return HomeAssistantConfigurationStore(load: { box.value }, save: { box.value = $0 })
    }
}
