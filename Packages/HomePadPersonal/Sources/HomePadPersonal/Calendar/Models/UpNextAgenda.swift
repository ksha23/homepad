import Foundation

/// What the Up Next widget lists: the events of one day and which day that is,
/// so the widget's header always names the day its events belong to.
public struct UpNextAgenda: Equatable, Sendable {
    /// The start of the day the events belong to.
    public var day: Date
    /// True once today has nothing left and the widget looks ahead to tomorrow.
    public var isTomorrow: Bool
    public var events: [PersonalEvent]

    public init(day: Date, isTomorrow: Bool, events: [PersonalEvent]) {
        self.day = day
        self.isTomorrow = isTomorrow
        self.events = events
    }

    /// When the list next changes on its own: when one of today's timed events
    /// ends and drops off, or at midnight, when the next day's list takes over.
    /// Calendar edits change it too, and the service reports those separately.
    public func nextChange(after now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86_400)
        let firstEnd = events.lazy.filter { !$0.isAllDay && $0.end > now }.map(\.end).min()
        return min(firstEnd ?? midnight, midnight)
    }
}
