import HomePadCore

/// Builds and splits the backend-prefixed IDs every accessory, scene and camera carries,
/// for example `ha:light.kitchen`, `hk:<uuid>` or `demo:lock.front`.
/// The prefix is how the unified service routes a command to the right backend.
enum BackendID {
    static func prefix(for backend: SmartHomeBackend) -> String {
        switch backend {
        case .homeKit: "hk"
        case .homeAssistant: "ha"
        case .demo: "demo"
        }
    }

    /// `make(.homeAssistant, "light.kitchen")` is `ha:light.kitchen`.
    static func make(_ backend: SmartHomeBackend, _ localID: String) -> String {
        "\(prefix(for: backend)):\(localID)"
    }

    /// The backend an ID belongs to, or nil when it has no known prefix.
    static func backend(of id: String) -> SmartHomeBackend? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        let prefix = id[..<colon]
        return SmartHomeBackend.allCases.first { self.prefix(for: $0) == prefix }
    }

    /// The backend's own ID, for example `light.kitchen` for `ha:light.kitchen`.
    static func localID(of id: String) -> String {
        guard backend(of: id) != nil, let colon = id.firstIndex(of: ":") else { return id }
        return String(id[id.index(after: colon)...])
    }
}
