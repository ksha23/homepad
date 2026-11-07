import Foundation
import HomePadCore

/// When Up Next and Weather ask a widget stack to show them (Core's
/// `WidgetRelevance`, for Smart Rotate). Plain functions of what the widgets
/// show and the time, so the rules read on their own.
enum PersonalWidgetRelevance {
    /// How long before an event Up Next asks to be shown: the half hour in
    /// which someone glances at it to leave on time.
    static let eventLead: TimeInterval = 30 * 60
    /// How far ahead Weather looks for rain or snow: the couple of hours that
    /// decide whether to take an umbrella or move the laundry in.
    static let weatherLead: TimeInterval = 2 * 60 * 60

    /// Up Next's relevance from the calendar it lists. It reads the calendar's
    /// reload key, so the stack asks again whenever an event is added or
    /// changed, as the widget itself reloads.
    @MainActor
    static func upNext(_ calendar: HouseholdCalendarService, now: Date) -> WidgetRelevance? {
        _ = calendar.reloadKey
        return upNext(calendar.upNext(now: now), now: now)
    }

    /// Up Next in the half hour before a timed event and while it runs, until
    /// the soonest such event ends. Otherwise it asks to be looked at again
    /// half an hour before the next one. All-day events never ask.
    static func upNext(_ agenda: UpNextAgenda, now: Date) -> WidgetRelevance? {
        let timed = agenda.events.filter { !$0.isAllDay && $0.end > now }
        let soon = timed.filter { $0.start.addingTimeInterval(-eventLead) <= now }
        if let ends = soon.map(\.end).min() { return .timely(until: ends) }
        guard let next = timed.map(\.start).min() else { return nil }
        return .notYet(until: next.addingTimeInterval(-eventLead))
    }

    /// Weather while rain, snow or sleet is forecast in the next couple of
    /// hours, until that hour has passed, and more urgently for a storm or
    /// hail, freezing rain or heavy snow. The forecast carries no weather
    /// alerts, so those severe conditions stand in for one. Without anything
    /// coming it asks to be looked at again a couple of hours before the next
    /// wet hour it knows of.
    static func weather(_ forecast: WeatherForecast?, now: Date) -> WidgetRelevance? {
        guard let forecast else { return nil }
        let hour: TimeInterval = 60 * 60
        let wet = forecast.upcomingHours(at: now).filter { $0.condition.precipitation != .none }
        let coming = wet.filter { $0.date < now.addingTimeInterval(weatherLead) }
        if let first = coming.first {
            let until = first.date.addingTimeInterval(hour)
            return coming.contains { isSevere($0.condition) } ? .needsLook(until: until) : .timely(until: until)
        }
        guard let later = wet.first else { return nil }
        return .notYet(until: later.date.addingTimeInterval(-weatherLead))
    }

    /// Weather that warrants an alert: storms, hail, freezing rain and heavy snow.
    static func isSevere(_ condition: WeatherConditionKind) -> Bool {
        switch condition {
        case .thunderstorm, .hail, .freezingRain, .heavySnow: true
        default: false
        }
    }
}
