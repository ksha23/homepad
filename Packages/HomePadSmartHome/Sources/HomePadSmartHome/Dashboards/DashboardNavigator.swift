import HomePadCore
import Observation

/// Lets any Smart Home screen open the Dashboards app at a Home Assistant path,
/// for things HomePad does not render natively.
@MainActor
@Observable
final class DashboardNavigator {
    static let appID = "dashboards"

    /// The path the Dashboards app should show next, for example `/history?entity_id=light.kitchen`.
    private(set) var requestedPath: String?
    @ObservationIgnored private let events: EventBus

    init(events: EventBus) {
        self.events = events
    }

    func open(path: String) {
        requestedPath = path
        events.post(.openApp(id: Self.appID))
    }

    /// Returns and clears the pending path.
    func takeRequestedPath() -> String? {
        defer { requestedPath = nil }
        return requestedPath
    }
}
