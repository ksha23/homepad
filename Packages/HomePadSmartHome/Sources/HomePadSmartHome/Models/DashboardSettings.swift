import Foundation

/// The Dashboards app's choices: which Home Assistant dashboard view to show
/// and a short list of curated web panels such as Frigate or Grafana.
struct DashboardSettings: Codable, Hashable, Sendable {
    /// Path inside Home Assistant, for example `/lovelace/0` or `/dashboard-kitchen/main`.
    var dashboardPath: String = "/lovelace/0"
    var panels: [WebPanel] = []
}

/// A curated web page shown in the Dashboards app with HomePad chrome around it.
struct WebPanel: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var symbol: WebPanelSymbol
    var url: String

    var resolvedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "http://\(trimmed)")
    }
}

/// The small fixed set of icons a web panel can use.
enum WebPanelSymbol: String, Codable, Hashable, Sendable, CaseIterable {
    case video = "video.fill"
    case chart = "chart.xyaxis.line"
    case bolt = "bolt.fill"
    case leaf = "leaf.fill"
    case shield = "shield.lefthalf.filled"
    case server = "server.rack"
    case house = "house.fill"
    case globe = "globe"
}
