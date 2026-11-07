import HomePadUI
import SwiftUI

/// The left pane of the Calendar's day view in landscape: the weekday and a
/// big day number with a count of events, over a small month to jump to
/// another day.
struct DaySummaryPanel: View {
    @Binding var selectedDate: Date
    let eventCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.red)
                Text(selectedDate.formatted(.dateTime.day()))
                    .font(.display(140, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(summary)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.standard, value: eventCount)
            }
            MiniMonth(selectedDate: $selectedDate)
                .padding(Theme.Spacing.m)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
    }

    private var summary: String {
        switch eventCount {
        case 0: "Nothing scheduled"
        case 1: "1 event"
        default: "\(eventCount) events"
        }
    }
}

/// A small month of tappable days, the selected one circled in red.
private struct MiniMonth: View {
    @Binding var selectedDate: Date
    /// The red circle slides from the old day to the new one.
    @Namespace private var selection

    var body: some View {
        let calendar = Calendar.current
        let days = CalendarDateMath.monthGrid(containing: selectedDate)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { _, day in
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
            }
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                let inMonth = calendar.isDate(day, equalTo: selectedDate, toGranularity: .month)
                Button {
                    withAnimation(Theme.Motion.standard) { selectedDate = day }
                } label: {
                    Text(day.formatted(.dateTime.day()))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(dayStyle(isSelected: isSelected, isToday: calendar.isDateInToday(day), inMonth: inMonth))
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .background { if isSelected { Circle().fill(.red).matchedGeometryEffect(id: "selection", in: selection) } }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func dayStyle(isSelected: Bool, isToday: Bool, inMonth: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        if isToday { return AnyShapeStyle(.red) }
        return inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
    }
}
