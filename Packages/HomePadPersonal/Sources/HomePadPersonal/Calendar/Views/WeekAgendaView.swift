import HomePadUI
import SwiftUI

/// Seven columns, one per day, with compact event cards.
struct WeekAgendaView: View {
    @Binding var selectedDate: Date
    let events: [PersonalEvent]
    let onSelect: (PersonalEvent) -> Void
    let onOpenDay: (Date) -> Void

    var body: some View {
        let days = CalendarDateMath.week(containing: selectedDate)
        GeometryReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    ForEach(days, id: \.self) { day in
                        column(for: day)
                            .frame(minHeight: proxy.size.height - Theme.Spacing.xl, alignment: .top)
                            .background(.primary.opacity(Calendar.current.isDateInToday(day) ? 0.09 : 0.04),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func column(for day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayEvents = events.filter { $0.overlaps(day: day) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { onOpenDay(day) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.headline)
                        .foregroundStyle(isToday ? .red : .secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.display(34))
                        .foregroundStyle(isToday ? .red : .primary)
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar.week.\(day.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))")
            ForEach(dayEvents) { event in
                Button { onSelect(event) } label: {
                    if event.isAllDay {
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: event.colorHex).opacity(0.45), in: Capsule())
                    } else {
                        EventCard(event: event, isCompact: true)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
