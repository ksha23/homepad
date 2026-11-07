import HomePadCore
import HomePadUI
import SwiftUI

/// Today's remaining events as a compact list with colored bars, like the
/// calendar complication on HomeView's Modular face.
///
/// Titles wrap to up to three lines, and the list shows as many events with
/// whole titles as fit its frame (measured, not estimated), so a long Canvas
/// assignment reads in full and the last row is never cut off. Rather than
/// show fewer than three events, titles get shorter (`EventListFit`), so the
/// next few events always show.
///
/// The list draws the events it is given. While nobody is recognized those
/// are the shared calendars' events only, and the shell's profile dot in the
/// face's corner says so, not a line in the list.
struct EventsList: View {
    let events: [CalendarItem]
    let now: Date
    /// The most event rows to try. Fewer show when they do not fit.
    let maxRows: Int
    let palette: FacePalette
    let fontSize: CGFloat

    /// True when there is anything to list after `now`.
    static func hasAgenda(_ events: [CalendarItem], after now: Date) -> Bool {
        events.contains(where: \.isAllDay) || !CalendarVisibility.upcoming(events, after: now).isEmpty
    }

    var body: some View {
        let items = listed
        let fits = EventListFit.candidates(eventCount: items.count, maxRows: maxRows)
        // The first layout that fits, in `EventListFit`'s order: whole titles
        // down to three events, then shorter titles, then fewer events.
        ViewThatFits(in: .vertical) {
            ForEach(Array(fits.enumerated()), id: \.offset) { _, fit in
                list(items, fit: fit)
            }
        }
    }

    /// All-day events first, then what is still to come today. All-day events
    /// are rows like the rest: Canvas quizzes and assignments come in as
    /// all-day events, and a one-line label cut their names off.
    private var listed: [CalendarItem] {
        events.filter(\.isAllDay) + CalendarVisibility.upcoming(events, after: now)
    }

    private func list(_ items: [CalendarItem], fit: EventListFit) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(items.prefix(fit.rows)) { item in
                row(item, titleLines: fit.titleLines, size: fontSize * fit.scale)
            }
            if items.count > fit.rows {
                // Lined up with the titles, past the bars, like HomeView's.
                Text(items.count - fit.rows == 1 ? "1 more event" : "\(items.count - fit.rows) more events")
                    .font(.display(fontSize * 0.75, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.leading, Self.barIndent(fontSize * fit.scale))
            }
            if items.isEmpty {
                EventsHint(palette: palette, fontSize: fontSize)
            }
        }
    }

    /// How far a row's text starts from its leading edge: the bar and the gap after it.
    private static func barIndent(_ fontSize: CGFloat) -> CGFloat {
        barWidth(fontSize) + fontSize * 0.45
    }

    private static func barWidth(_ fontSize: CGFloat) -> CGFloat {
        max(fontSize * 0.16, 3)
    }

    private func row(_ item: CalendarItem, titleLines: Int, size fontSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: fontSize * 0.45) {
            Capsule()
                .fill(barColor(item))
                .frame(width: Self.barWidth(fontSize))
            VStack(alignment: .leading, spacing: 0) {
                // Smaller than the title, which carries the row from across the
                // room. It shrinks a little rather than lose the end time.
                Text(timeText(item))
                    .font(.display(fontSize * 0.7, weight: .semibold))
                    .foregroundStyle(item.start <= now ? palette.accent : palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(item.title)
                    .font(.display(fontSize, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(titleLines)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timeText(_ item: CalendarItem) -> String {
        if item.isAllDay { return "All day" }
        // Due dates (Canvas assignments, for one) start and end at the same minute.
        return item.end > item.start
            ? (item.start..<item.end).formatted(.interval.hour().minute())
            : item.start.formatted(date: .omitted, time: .shortened)
    }

    private func barColor(_ item: CalendarItem) -> Color {
        if palette.isNight { return palette.accent }
        return item.colorHex.map { Color(hex: $0) } ?? palette.accent
    }
}

/// The one line shown when there is nothing to list: "No more events today".
struct EventsHint: View {
    let palette: FacePalette
    let fontSize: CGFloat

    var body: some View {
        Label("No more events today", systemImage: "calendar")
            .font(.display(fontSize * 0.85, weight: .medium))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
