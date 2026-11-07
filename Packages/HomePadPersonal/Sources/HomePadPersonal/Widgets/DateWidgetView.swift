import HomePadCore
import HomePadUI
import SwiftUI

/// Today's date in big type, with the month grid on the large size. The number
/// shrinks before anything would run past the tile. It redraws at midnight,
/// the only time it changes.
struct DateWidgetView: View {
    let size: WidgetSize

    var body: some View {
        // A solid card, white by day and black at night, like HomeView's Calendar widget.
        GlassTile(surface: .solid) {
            ClockTimeline(every: .day) { date in
                ViewThatFits(in: .vertical) {
                    switch size {
                    case .small:
                        stacked(date, day: 72)
                        stacked(date, day: 56)
                        stacked(date, day: 44)
                    case .medium:
                        // The number beside the weekday and month uses the tile's width.
                        sideBySide(date, day: 84)
                        sideBySide(date, day: 64)
                        sideBySide(date, day: 48)
                    // Tall is not offered (`WidgetSize.standard`). It would hold the same month.
                    case .large, .tall:
                        month(date, day: 64)
                        month(date, day: 44)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .small ? .center : .leading)
                // At midnight the number rolls to the next day and the rest crossfades.
                .animation(Theme.Motion.standard, value: Calendar.current.startOfDay(for: date))
            }
        }
    }

    private func weekday(_ date: Date) -> some View {
        Text(date, format: .dateTime.weekday(.wide)).font(.headline).foregroundStyle(.red).textCase(.uppercase)
    }

    private func dayNumber(_ date: Date, size: CGFloat) -> some View {
        Text(date, format: .dateTime.day())
            .font(.display(size))
            .contentTransition(.numericText())
    }

    private func stacked(_ date: Date, day: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            weekday(date)
            dayNumber(date, size: day)
            Text(date, format: .dateTime.month(.wide).year()).font(.headline).foregroundStyle(.secondary)
        }
    }

    private func sideBySide(_ date: Date, day: CGFloat) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            dayNumber(date, size: day)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                weekday(date)
                Text(date, format: .dateTime.month(.wide).year()).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func month(_ date: Date, day: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            weekday(date)
            HStack(alignment: .firstTextBaseline) {
                dayNumber(date, size: day)
                Text(date, format: .dateTime.month(.wide)).font(.title2.weight(.semibold))
            }
            miniMonth(date)
        }
    }

    private func miniMonth(_ date: Date) -> some View {
        let days = CalendarDateMath.monthGrid(containing: date)
        let calendar = Calendar.current
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(days.prefix(7), id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDate(day, inSameDayAs: date)
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? AnyShapeStyle(.white) : (calendar.isDate(day, equalTo: date, toGranularity: .month) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
                    .frame(width: 28, height: 28)
                    .background { if isToday { Circle().fill(.red) } }
            }
        }
    }
}
