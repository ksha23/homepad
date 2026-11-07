import Foundation
import HAKit
import HomePadCore

/// One Home Assistant dashboard view the person can pick, such as "Overview, Kitchen".
struct DashboardOption: Hashable, Identifiable, Sendable {
    var title: String
    /// Frontend path, for example `/lovelace/0` or `/dashboard-tablet/kitchen`.
    var path: String
    var id: String { path }
}

/// Lists Home Assistant's dashboards and their views for the path picker.
enum HADashboardCatalog {
    /// The default dashboard plus every storage dashboard from `lovelace/dashboards/list`.
    static func dashboards(from result: JSONValue) -> [(urlPath: String?, title: String)] {
        let extra = (result.arrayValue ?? []).compactMap { item -> (String?, String)? in
            guard let path = item["url_path"]?.stringValue else { return nil }
            return (path, item["title"]?.stringValue ?? path)
        }
        return [(nil, "Overview")] + extra
    }

    /// The views of one dashboard config (`lovelace/config`). Views without a path use their index.
    static func views(from config: JSONValue, urlPath: String?, dashboardTitle: String) -> [DashboardOption] {
        let base = urlPath ?? "lovelace"
        let views = config["views"]?.arrayValue ?? []
        guard !views.isEmpty else { return [DashboardOption(title: dashboardTitle, path: "/\(base)/0")] }
        return views.enumerated().map { index, view in
            let path = view["path"]?.stringValue ?? "\(index)"
            let title = view["title"]?.stringValue ?? "View \(index + 1)"
            return DashboardOption(title: "\(dashboardTitle), \(title)", path: "/\(base)/\(path)")
        }
    }

    /// Every view of every dashboard. Dashboards whose config cannot load (YAML errors,
    /// strategies) still appear with their first view.
    @MainActor
    static func load(from connection: HAConnection) async -> [DashboardOption] {
        let list = (try? await connection.send(HARequests.dashboards)).map(JSONValue.init(haData:)) ?? .array([])
        var options: [DashboardOption] = []
        for dashboard in dashboards(from: list) {
            let config = (try? await connection.send(HARequests.dashboardConfig(urlPath: dashboard.urlPath))).map(JSONValue.init(haData:)) ?? .null
            options += views(from: config, urlPath: dashboard.urlPath, dashboardTitle: dashboard.title)
        }
        return options
    }
}
