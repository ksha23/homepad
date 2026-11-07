import Foundation
import HAKit
import HomePadCore

/// The Home Assistant requests HomePad sends through HAKit.
enum HARequests {
    /// REST `GET /api/states`, the initial load.
    static let states = HARequest(type: .rest(.get, "states"))
    /// REST `GET /api/config`, for the location name and temperature unit.
    static let config = HARequest(type: .rest(.get, "config"))
    static let areaRegistry = HARequest(type: "config/area_registry/list")
    static let deviceRegistry = HARequest(type: "config/device_registry/list")
    static let entityRegistry = HARequest(type: "config/entity_registry/list")
    static let dashboards = HARequest(type: "lovelace/dashboards/list")

    /// Any WebSocket command with its top-level fields, for `SmartHomeService.sendCommand`.
    /// Not retried, because action calls must not run twice.
    static func command(_ type: String, data: [String: Any]) -> HARequest {
        HARequest(type: .webSocket(type), data: data, shouldRetry: false)
    }

    /// Asks Home Assistant for an HLS playlist of a camera.
    static func cameraStream(_ entityID: String) -> HARequest {
        HARequest(type: "camera/stream", data: ["entity_id": entityID], shouldRetry: false)
    }

    /// A dashboard's config, for listing its views. Nil is the default dashboard.
    static func dashboardConfig(urlPath: String?) -> HARequest {
        HARequest(type: "lovelace/config", data: urlPath.map { ["url_path": $0] } ?? [:], shouldRetry: false)
    }

    /// REST history for one entity since a date, without attributes.
    static func history(_ entityID: String, since: Date) -> HARequest {
        let start = since.formatted(.iso8601)
        return HARequest(type: .rest(.get, "history/period/\(start)"), queryItems: [
            URLQueryItem(name: "filter_entity_id", value: entityID),
            URLQueryItem(name: "minimal_response", value: nil),
            URLQueryItem(name: "no_attributes", value: nil),
        ], shouldRetry: false)
    }
}
