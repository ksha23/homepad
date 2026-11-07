import HomePadCore
import HomePadUI
import SwiftUI

/// Today's events from calendars the current viewer may see and left checked,
/// like HomeView's Calendar widget that lists the day's events. Once today has
/// nothing left it shows tomorrow under a Tomorrow label. The events come from
/// `HouseholdCalendarService.upNext`, the same day lists the Calendar app shows.
/// An event under way says Now, and one that ends fades out as the rest move up.
///
/// The tall size lists more of the day, and when today's events leave room
/// under them it goes on with tomorrow's, under a Tomorrow label
/// (`upNextFollowingDay(after:)`).
struct UpNextWidgetView: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition
    let size: WidgetSize
    @State private var agenda = UpNextAgenda(day: Date(), isTomorrow: false, events: [])
    /// Tomorrow's events, for the room under today's on the tall size. Empty on other sizes.
    @State private var nextDay: [PersonalEvent] = []
    /// The events under way, which show Now instead of their start.
    @State private var happening: Set<PersonalEvent.ID> = []

    private var events: [PersonalEvent] { agenda.events }

    /// The most events a size lists from one day. The tall size has room for about half as many again.
    private var mostEvents: Int { size == .tall ? 12 : 8 }

    var body: some View {
        // A solid card, white by day and black at night, like HomeView's Calendar widget.
        GlassTile(surface: .solid) {
            if events.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    header(more: 0)
                    Spacer(minLength: 0)
                    Text(calendar.hasAccess ? "No more events today" : "Open Calendar to connect calendars")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                // As many events as fit the tile with whole titles (up to three
                // lines), so a tall tile never sits half empty, a short one never
                // spills, and a long Canvas quiz name is not cut off. The header
                // counts the rest, which saves the medium tile a line. On the tall
                // size, every event of today with some of tomorrow's under them
                // comes first.
                // One list with an ID for each choice: ViewThatFits stopped the app
                // when two lists of counts gave two choices the same ID.
                ViewThatFits(in: .vertical) {
                    ForEach(Self.fits(events: events.count, nextDay: nextDay.count, most: mostEvents), id: \.self) { fit in
                        content(fit.count, later: fit.later, titleLines: fit.titleLines)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // Reloads when calendars change, and again when the list changes on its
        // own: as an event starts, as one ends and drops off, and at midnight.
        // Nothing else changes it, so the widget does not ask EventKit every
        // minute. A thumbnail and a sleeping display load once and wait.
        .task(id: Reload(key: calendar.reloadKey, size: size, isPaused: isThumbnail || displayCondition == .sleeping)) {
            while !Task.isCancelled {
                let now = Date()
                let next = calendar.upNext(now: now)
                let later = size == .tall ? calendar.upNextFollowingDay(after: next) : []
                let underWay = Self.happening(next.events, at: now)
                if next != agenda || later != nextDay || underWay != happening {
                    // The first load appears as is. Later changes settle into place.
                    withAnimation(agenda.events.isEmpty ? nil : Theme.Motion.standard) {
                        agenda = next
                        nextDay = later
                        happening = underWay
                    }
                }
                guard !(isThumbnail || displayCondition == .sleeping) else { return }
                // At most half an hour, so a change of clock or time zone catches up.
                let wake = min(next.nextChange(after: now), Self.nextStart(of: next.events, after: now) ?? .distantFuture)
                let wait = min(wake.timeIntervalSince(now), Self.longestWait)
                try? await Task.sleep(for: .seconds(max(wait, 1)))
            }
        }
    }

    private static let longestWait: TimeInterval = 30 * 60

    /// Timed events that have started and not yet ended.
    static func happening(_ events: [PersonalEvent], at now: Date) -> Set<PersonalEvent.ID> {
        Set(events.filter { !$0.isAllDay && $0.start <= now && now < $0.end }.map(\.id))
    }

    /// When the next timed event starts, so the widget can say Now.
    static func nextStart(of events: [PersonalEvent], after now: Date) -> Date? {
        events.lazy.filter { !$0.isAllDay && $0.start > now }.map(\.start).min()
    }

    /// One way to fill the tile: how many of the day's events, how many of
    /// tomorrow's under them, and how many lines each title may take.
    struct Fit: Hashable {
        var count: Int
        var later = 0
        var titleLines = 3
    }

    /// The ways to fill the tile, most first, for `ViewThatFits`: every event
    /// of the day with as many of tomorrow's as there are (only on the tall
    /// size, which loads them), then fewer of the day's, then one event with
    /// shorter titles.
    static func fits(events: Int, nextDay: Int, most: Int) -> [Fit] {
        guard events > 0 else { return [Fit(count: 0)] }
        let later = nextDay > 0 && events <= most
            ? (1...min(nextDay, most)).reversed().map { Fit(count: events, later: $0) } : []
        let today = (1...min(events, most)).reversed().map { Fit(count: $0) }
        return later + today + [Fit(count: 1, titleLines: 2), Fit(count: 1, titleLines: 1)]
    }

    /// What the event list depends on, besides the time.
    private struct Reload: Hashable {
        var key: String
        var size: WidgetSize
        var isPaused: Bool
    }

    /// - Parameters:
    ///   - count: How many of the agenda's events to list.
    ///   - later: How many of tomorrow's events to list under them, on the tall size.
    private func content(_ count: Int, later: Int = 0, titleLines: Int) -> some View {
        let more = events.count - count
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header(more: agenda.isTomorrow ? 0 : more)
            if agenda.isTomorrow {
                tomorrowLabel(more: more)
            }
            ForEach(events.prefix(count)) { event in
                row(event, on: agenda.day, titleLines: titleLines)
            }
            moreLine(more)
            if later > 0, let day = Calendar.current.date(byAdding: .day, value: 1, to: agenda.day) {
                tomorrowLabel(more: nextDay.count - later)
                    .padding(.top, Theme.Spacing.xs)
                ForEach(nextDay.prefix(later)) { event in
                    row(event, on: day, titleLines: titleLines)
                }
            }
        }
    }

    /// "Tomorrow", with how many of its events did not fit.
    private func tomorrowLabel(more: Int) -> some View {
        Text(more > 0 ? "Tomorrow · \(more) more" : "Tomorrow")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Today's weekday, how many of today's events did not fit, and the day of
    /// the month. A small tile has room for "WED" and the date only: the whole
    /// weekday and the count were cut to "Wedn… · 2 m…", so the count moves
    /// under the events there (`moreLine`).
    private func header(more: Int) -> some View {
        let isSmall = size == .small
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(Date(), format: .dateTime.weekday(isSmall ? .abbreviated : .wide))
                .font(.headline.weight(.bold))
                .textCase(isSmall ? .uppercase : nil)
                .foregroundStyle(.red)
            if more > 0, !isSmall {
                Text("· \(more) more").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(Date(), format: .dateTime.day()).font(.display(size.rows >= 2 ? 34 : 26))
                .contentTransition(.numericText())
        }
        .lineLimit(1)
    }

    /// On a small tile, how many of today's events did not fit, under the list.
    @ViewBuilder
    private func moreLine(_ more: Int) -> some View {
        if size == .small, more > 0, !agenda.isTomorrow {
            Text(more == 1 ? "1 more event" : "\(more) more events")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// One event, listed under `day`.
    private func row(_ event: PersonalEvent, on day: Date, titleLines: Int) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.headline).lineLimit(titleLines)
                Text(timeText(event, on: day))
                    .font(.subheadline.weight(happening.contains(event.id) ? .semibold : .regular))
                    .foregroundStyle(happening.contains(event.id) ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .contentTransition(.interpolate)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timeText(_ event: PersonalEvent, on listed: Date) -> String {
        if event.isAllDay { return "All day" }
        if happening.contains(event.id) {
            // "Now · until 3:00 PM", or just Now when it runs past today.
            guard Calendar.current.isDate(event.end, inSameDayAs: listed) else { return "Now" }
            return "Now · until " + event.end.formatted(date: .omitted, time: .shortened)
        }
        // An event that began on an earlier day says so.
        let day = Calendar.current.isDate(event.start, inSameDayAs: listed) ? "" : event.start.formatted(.dateTime.weekday(.abbreviated)) + " "
        return day + event.start.formatted(date: .omitted, time: .shortened)
    }
}
