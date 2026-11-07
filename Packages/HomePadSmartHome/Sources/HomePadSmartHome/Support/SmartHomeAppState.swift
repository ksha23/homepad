import Foundation
import HomePadCore

/// What the Home and Dashboards apps keep between openings (see `@AppState`).
/// Shared by the household, like the home itself.
enum SmartHomeAppState {
    /// The room picked in the Home app. Nil is All Rooms.
    static let room = AppStateKey<String?>("home.room", default: nil)
    /// The accessory whose full-screen controls are open.
    static let accessory = AppStateKey<HomeAccessory.ID?>("home.accessory", default: nil)
    /// The camera open full screen.
    static let camera = AppStateKey<HomeCamera.ID?>("home.camera", default: nil)
    /// Whether the grid of every camera is open.
    static let allCameras = AppStateKey("home.allCameras", default: false)
    /// The page Dashboards shows.
    static let dashboard = AppStateKey("dashboards.page", default: DashboardSelection.homeAssistant)
}

/// A page the Dashboards app can show: the Home Assistant dashboard or one of
/// the web panels, by identifier.
enum DashboardSelection: Codable, Hashable, Sendable {
    case homeAssistant
    case panel(UUID)
}
