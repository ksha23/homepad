import HomePadUI
import SwiftUI

/// The days an alarm repeats: a round button per day, filled when chosen, in
/// the order the locale's week runs. Under them, "Weekdays" or "Once" says
/// what the choice means.
struct WeekdayPicker: View {
    @Binding var weekdays: Set<Locale.Weekday>
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(AlarmFormat.orderedForWeek(Set(Locale.Weekday.ordered), calendar: calendar), id: \.self) { day in
                    dayButton(day)
                }
            }
            Text(AlarmFormat.repeatText(weekdays, calendar: calendar))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
                .animation(Theme.Motion.standard, value: weekdays)
        }
    }

    private func dayButton(_ day: Locale.Weekday) -> some View {
        let index = Locale.Weekday.ordered.firstIndex(of: day) ?? 0
        let isOn = weekdays.contains(day)
        return Button {
            if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(calendar.veryShortWeekdaySymbols[index])
                .font(.headline)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .background(Circle().fill(isOn ? Color.orange : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.pressable)
        .animation(Theme.Motion.standard, value: isOn)
        .accessibilityLabel(calendar.weekdaySymbols[index])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
