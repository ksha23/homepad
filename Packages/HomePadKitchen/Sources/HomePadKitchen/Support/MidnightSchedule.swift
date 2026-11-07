import SwiftUI

/// A `TimelineView` schedule for content that changes once a day: it ticks now
/// and then at each midnight, or only now while paused. Pause it inside
/// thumbnails and while the display sleeps.
struct MidnightSchedule: TimelineSchedule {
    let isPaused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let calendar = Calendar.current
        let isPaused = isPaused
        var upcoming: Date? = startDate
        return AnyIterator {
            guard let current = upcoming else { return nil }
            upcoming = isPaused ? nil : calendar.dateInterval(of: .day, for: current)?.end
            return current
        }
    }
}
