import HomePadCore
import SwiftUI

/// A `TimelineView` that redraws when the time it shows changes: at the start
/// of every second, minute, hour or day. It stops inside thumbnails and while
/// the display sleeps, where nothing can be seen to change, and draws the
/// current time again when it wakes. Candidate for HomePadUI.
///
///     ClockTimeline(every: .minute) { now in Text(now, format: .dateTime.hour().minute()) }
struct ClockTimeline<Content: View>: View {
    private let unit: TickSchedule.Unit
    private let content: (Date) -> Content
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition

    /// - Parameters:
    ///   - unit: The smallest step the content shows, such as `.minute` for a clock without seconds.
    ///   - content: Draws the view for a moment in time.
    init(every unit: TickSchedule.Unit, @ViewBuilder content: @escaping (Date) -> Content) {
        self.unit = unit
        self.content = content
    }

    var body: some View {
        TimelineView(TickSchedule(unit, isPaused: isThumbnail || displayCondition == .sleeping)) { context in
            content(context.date)
        }
    }
}

/// Ticks now and then at the start of each second, minute, hour or day, or
/// only now while paused. One schedule type for every unit, so a change of
/// unit or a pause keeps the timeline's identity.
struct TickSchedule: TimelineSchedule {
    enum Unit: Sendable {
        case second, minute, hour, day

        /// The first boundary after `date`. Hours and days follow the calendar,
        /// so half-hour time zones and daylight saving changes land right.
        func boundary(after date: Date, calendar: Calendar) -> Date {
            switch self {
            case .second: aligned(after: date, step: 1)
            case .minute: aligned(after: date, step: 60)
            case .hour: calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
            case .day: calendar.dateInterval(of: .day, for: date)?.end ?? date.addingTimeInterval(86_400)
            }
        }

        private func aligned(after date: Date, step: TimeInterval) -> Date {
            Date(timeIntervalSinceReferenceDate: ((date.timeIntervalSinceReferenceDate / step).rounded(.down) + 1) * step)
        }
    }

    let unit: Unit
    let isPaused: Bool

    init(_ unit: Unit, isPaused: Bool = false) {
        self.unit = unit
        self.isPaused = isPaused
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(upcoming: startDate, unit: isPaused ? nil : unit, calendar: .current)
    }

    /// `startDate`, then each boundary after it. Ends after the first date when paused.
    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let unit: Unit?
        let calendar: Calendar

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = unit?.boundary(after: current, calendar: calendar)
            return current
        }
    }
}
