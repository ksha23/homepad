import HomePadCore
import HomePadUI
import SwiftUI

/// Events grouped by day with tinted rows, like HomeView's calendar answers.
struct CalendarCardView: View {
    /// The card's events by day, read once from its payload. Rows are numbered
    /// by position: a new UUID on every read gave each row a new identity, so
    /// SwiftUI rebuilt every row with each streamed word of the answer.
    private let days: [Day]
    @Environment(\.colorScheme) private var colorScheme

    private struct Event: Identifiable {
        let id: Int
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String
        let color: Color
        let isReminder: Bool
    }

    private struct Day: Identifiable {
        let date: Date
        let events: [Event]
        var id: Date { date }
    }

    init(card: AssistantCard) {
        let events = (card.payload["events"]?.arrayValue ?? []).enumerated().map { index, item in
            let hex = item["color"]?.stringValue ?? ""
            return Event(
                id: index,
                title: item["title"]?.stringValue ?? "",
                start: Date(timeIntervalSince1970: item["start"]?.doubleValue ?? 0),
                end: Date(timeIntervalSince1970: item["end"]?.doubleValue ?? 0),
                isAllDay: item["allDay"]?.boolValue ?? false,
                location: item["location"]?.stringValue ?? "",
                color: hex.isEmpty ? (item["reminder"]?.boolValue == true ? .orange : .blue) : Color(hex: hex),
                isReminder: item["reminder"]?.boolValue ?? false
            )
        }
        let byDay = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.start) }
        days = byDay.keys.sorted().map { Day(date: $0, events: byDay[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(days) { day in
                SectionHeader(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                ForEach(day.events) { event in
                    row(event)
                }
            }
        }
    }

    private func row(_ event: Event) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            if event.isAllDay || event.isReminder {
                Image(systemName: event.isReminder ? "checklist" : "calendar")
                    .font(.title3)
                    .foregroundStyle(event.color)
            } else {
                Capsule().fill(event.color).frame(width: 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.title3.weight(.semibold))
                if !event.isAllDay, !event.isReminder {
                    Label(timeRange(event), systemImage: "clock").font(.callout)
                }
                if !event.location.isEmpty {
                    Text(event.location).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if event.isAllDay { Text("all-day").font(.callout).foregroundStyle(.secondary) }
        }
        // The event's color lightened in Dark and deepened in Light, so the
        // text reads on its tinted row in either appearance.
        .foregroundStyle(colorScheme == .light ? event.color.mix(with: .black, by: 0.45) : event.color.mix(with: .white, by: 0.55))
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.color.opacity(0.22), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func timeRange(_ event: Event) -> String {
        "\(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}
