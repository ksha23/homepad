import HomePadUI
import SwiftUI

/// A month grid with as many events of each day as its cell holds, then how
/// many more there are. Tapping a day opens it.
struct MonthGridView: View {
    let selectedDate: Date
    let events: [PersonalEvent]
    let onOpenDay: (Date) -> Void

    var body: some View {
        let days = CalendarDateMath.monthGrid(containing: selectedDate)
        let rows = max(1, days.count / 7)
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { proxy in
                let height = (proxy.size.height - Theme.Spacing.xs * CGFloat(rows - 1)) / CGFloat(rows)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 7), spacing: Theme.Spacing.xs) {
                    ForEach(days, id: \.self) { day in
                        Button { onOpenDay(day) } label: {
                            cell(for: day).frame(height: max(60, height))
                        }
                        .buttonStyle(.pressable(scale: 0.97))
                    }
                }
            }
        }
    }

    private func cell(for day: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: selectedDate, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let dayEvents = events.filter { $0.overlaps(day: day) }
        return VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.title3.weight(.semibold))
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
                .frame(width: 36, height: 36)
                .background { if isToday { Circle().fill(.red) } }
            // The most lines the cell holds: four in a tall cell, fewer in the
            // shorter rows of the 11-inch or a six-week month.
            ViewThatFits(in: .vertical) {
                eventLines(dayEvents, lines: 4)
                eventLines(dayEvents, lines: 3)
                eventLines(dayEvents, lines: 2)
                eventLines(dayEvents, lines: 1)
            }
        }
        .padding(Theme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.primary.opacity(inMonth ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .opacity(inMonth ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    /// Up to `lines` lines of a day's events. When they do not all fit, the
    /// last line says how many more there are instead. A month grid is a dense
    /// overview, so its lines take the dense floor, Subheadline.
    private func eventLines(_ events: [PersonalEvent], lines: Int) -> some View {
        let shown = events.count > lines ? lines - 1 : events.count
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(events.prefix(shown)) { event in
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: event.colorHex)).frame(width: 8, height: 8)
                    Text(event.title).font(.subheadline).lineLimit(1)
                }
            }
            if events.count > shown {
                Text("\(events.count - shown) more").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
