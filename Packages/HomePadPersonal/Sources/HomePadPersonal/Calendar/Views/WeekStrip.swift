import HomePadUI
import SwiftUI

/// The S M T W T F S row with the selected day circled in red.
struct WeekStrip: View {
    @Binding var selectedDate: Date
    /// The red circle slides from the old day to the new one.
    @Namespace private var selection

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(CalendarDateMath.week(containing: selectedDate), id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDateInToday(day)
                Button {
                    withAnimation(Theme.Motion.standard) { selectedDate = day }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.display(30))
                            .foregroundStyle(isSelected ? .white : (isToday ? .red : .primary))
                            .frame(width: 60, height: 60)
                            .background { if isSelected { Circle().fill(.red).matchedGeometryEffect(id: "selection", in: selection) } }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
