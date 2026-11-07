import ActivityKit
import Foundation
import HomePadCore
import WidgetKit

/// Mirrors timers to places outside the app: the Lock Screen Live Activity and
/// the Home Screen widget.
@MainActor
public protocol TimerSurfaceSyncing: AnyObject {
    func sync(_ timers: [HomeTimer])
}

/// Mirrors nothing, for tests.
@MainActor
public final class NoTimerSurfaces: TimerSurfaceSyncing {
    public init() {}
    public func sync(_ timers: [HomeTimer]) {}
}

/// Keeps one Live Activity for all active timers and publishes the same state to
/// the App Group for the widget extension.
///
/// One activity, not one per timer, keeps the Lock Screen calm with several
/// timers and stays well under the system's activity limit. On devices where Live
/// Activities are off or unsupported only the widget snapshot is written.
@MainActor
public final class TimerSurfaceSync: TimerSurfaceSyncing {
    private let liveActivitiesEnabled: () -> Bool
    private var lastState: TimerActivityAttributes.ContentState?
    /// Activity updates run one after another so two quick changes cannot request two activities.
    private var pending: Task<Void, Never>?
    private let log = Log.make("Kitchen.LiveActivity")

    /// - Parameter liveActivitiesEnabled: Reads the Kitchen setting at call time.
    public init(liveActivitiesEnabled: @escaping () -> Bool) {
        self.liveActivitiesEnabled = liveActivitiesEnabled
    }

    public func sync(_ timers: [HomeTimer]) {
        let state = Self.contentState(for: timers)
        guard state != lastState else { return }
        lastState = state
        TimerActivityAttributes.saveSnapshot(state)
        WidgetCenter.shared.reloadTimelines(ofKind: TimerActivityAttributes.homeWidgetKind)
        let previous = pending
        pending = Task {
            await previous?.value
            await updateActivity(with: state)
        }
    }

    /// Timers as the Lock Screen sees them, soonest first, finished ones last.
    static func contentState(for timers: [HomeTimer], now: Date = Date()) -> TimerActivityAttributes.ContentState {
        let entries = timers
            .sorted { lhs, rhs in
                if (lhs.status == .finished) != (rhs.status == .finished) { return rhs.status == .finished }
                return lhs.remaining(at: now) < rhs.remaining(at: now)
            }
            .map { timer in
                TimerActivityAttributes.Entry(
                    id: timer.id, label: timer.label, duration: timer.duration,
                    status: TimerActivityAttributes.Entry.Status(rawValue: timer.status.rawValue) ?? .running,
                    endDate: timer.endDate, pausedRemaining: timer.remainingWhenPaused)
            }
        return TimerActivityAttributes.ContentState(timers: entries)
    }

    private func updateActivity(with state: TimerActivityAttributes.ContentState) async {
        let activities = Activity<TimerActivityAttributes>.activities
        let wanted = liveActivitiesEnabled() && ActivityAuthorizationInfo().areActivitiesEnabled
            && state.timers.contains { $0.status != .finished }

        guard wanted else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let latestEnd = state.timers.compactMap(\.endDate).max() ?? Date()
        let content = ActivityContent(state: state, staleDate: latestEnd.addingTimeInterval(60))
        if let current = activities.first {
            await current.update(content)
            for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else {
            do {
                _ = try Activity.request(attributes: TimerActivityAttributes(title: "Kitchen Timers"), content: content)
            } catch {
                log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
