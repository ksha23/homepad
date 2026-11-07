import HomePadCore
import SwiftUI

/// Builds the glance from the services and hands it to its content.
///
/// Home, timers and weather are read in the body, so a light turning on
/// redraws the glance. Calendar and reminders come from `services.calendar`,
/// loaded again when calendars or who is looking change (`reloadKey`) and
/// whenever the summary would change on its own (`GlanceSummary.nextChange`).
/// Unread messages are the Messages app's own badge (`AppDescriptor.badgeCount`),
/// so the glance never imports Comms, and the count follows its settings: the
/// Messages store is locked, with nothing unread, whenever it may not show
/// anyone's messages. All three are personal, so they are read only while
/// someone is recognized.
struct GlanceReader<Content: View>: View {
    @ViewBuilder let content: (GlanceSummary) -> Content
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @State private var day = GlanceSummary.Personal()
    /// The time the summary was last worked out at, moved on by the reload loop.
    @State private var now = Date()

    var body: some View {
        let unlocked = household.isPersonalContentUnlocked
        var personal: GlanceSummary.Personal?
        if unlocked {
            personal = day
            personal?.unreadMessages = registry.app(GlanceAppID.messages)?.badgeCount?() ?? 0
        }
        let summary = GlanceSummary.make(personal: personal, accessories: services.smartHome.accessories,
                                         timers: services.timers.timers, weather: services.weather.current, now: now)
        return content(summary)
            .task(id: Reload(calendar: services.calendar.reloadKey, unlocked: unlocked)) {
                await follow(unlocked: unlocked)
            }
    }

    /// What the personal part depends on besides the time.
    private struct Reload: Hashable {
        var calendar: String
        var unlocked: Bool
    }

    /// Loads today's events and reminders, then again each time they would
    /// change, until the view goes or what it depends on changes.
    private func follow(unlocked: Bool) async {
        guard unlocked else {
            day = GlanceSummary.Personal()
            now = Date()
            return
        }
        while !Task.isCancelled {
            let start = Date()
            let calendar = Calendar.current
            let today = calendar.dateInterval(of: .day, for: start) ?? DateInterval(start: start, duration: 86_400)
            let events = await services.calendar.events(from: today.start, to: today.end)
            let reminders = await services.calendar.reminders(includeCompleted: false)
            guard !Task.isCancelled else { return }
            let loaded = GlanceSummary.Personal(events: events, reminders: reminders)
            day = loaded
            now = Date()
            let wait = GlanceSummary.nextChange(personal: loaded, now: now).timeIntervalSince(now)
            try? await Task.sleep(for: .seconds(max(wait, 1)))
        }
    }
}
