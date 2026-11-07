#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Live Activity attributes for HomePad's kitchen timers.
///
/// Shared by the app, which starts and updates one activity for all running
/// timers, and by the widget extension, which draws it on the Lock Screen.
/// The same `ContentState` is also written to the App Group so the Home Screen
/// timer widget can show the current timers without a Live Activity.
///
/// ActivityKit is iOS only (its types are unavailable on macOS), so the file
/// is guarded with `os(iOS)` as well as `canImport(ActivityKit)`.
public struct TimerActivityAttributes: ActivityAttributes {
    /// One timer as the Lock Screen and widgets see it.
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public enum Status: String, Codable, Sendable { case running, paused, finished }

        public var id: UUID
        public var label: String
        /// Total length in seconds, for the progress ring.
        public var duration: TimeInterval
        public var status: Status
        /// When a running timer ends.
        public var endDate: Date?
        /// Time left on a paused timer.
        public var pausedRemaining: TimeInterval?

        public init(id: UUID, label: String, duration: TimeInterval, status: Status,
                    endDate: Date?, pausedRemaining: TimeInterval?) {
            self.id = id
            self.label = label
            self.duration = duration
            self.status = status
            self.endDate = endDate
            self.pausedRemaining = pausedRemaining
        }

        /// Seconds left at `now`.
        public func remaining(at now: Date = Date()) -> TimeInterval {
            switch status {
            case .running: max(0, (endDate ?? now).timeIntervalSince(now))
            case .paused: pausedRemaining ?? duration
            case .finished: 0
            }
        }
    }

    /// Everything that changes while the activity runs.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Active timers, soonest first.
        public var timers: [Entry]

        public init(timers: [Entry]) {
            self.timers = timers
        }

        /// The timer to feature: the soonest running one, else the first.
        public var featured: Entry? {
            timers.first { $0.status == .running } ?? timers.first
        }
    }

    /// Shown above the timers, for example "Kitchen".
    public var title: String

    public init(title: String) {
        self.title = title
    }

    // MARK: Shared snapshot for widgets

    /// App Group shared by the app and the widget extension.
    public static let appGroup = "group.com.ksha23.homepad"
    /// UserDefaults key (in the App Group) holding the latest `ContentState` as JSON.
    public static let snapshotKey = "kitchen.timers.snapshot"
    /// WidgetKit kind of the Home Screen timers widget, for timeline reloads.
    public static let homeWidgetKind = "HomePadTimers"

    /// Reads the latest timers the app published. Nil when none were written yet.
    public static func loadSnapshot() -> ContentState? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ContentState.self, from: data)
    }

    /// Publishes the current timers for the widget extension.
    public static func saveSnapshot(_ state: ContentState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: snapshotKey)
    }
}
#endif
