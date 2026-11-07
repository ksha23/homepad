import HomePadCore
import HomePadUI
import SwiftUI

/// One alarm in the list, as in the Clock app: a big time with AM or PM, the
/// label and days under it, and a switch. Off alarms are dimmed. Tapping the
/// row opens the editor.
struct AlarmRow: View {
    let alarm: HomeAlarm
    let onEdit: () -> Void
    @Environment(AlarmService.self) private var service

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(AlarmFormat.clockTime(alarm))
                            .font(.display(64, weight: .light))
                        if let period = AlarmFormat.dayPeriod(alarm) {
                            Text(period).font(.title.weight(.light))
                        }
                    }
                    Text(subtitle)
                        .font(.title3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
            .accessibilityLabel("\(AlarmFormat.time(alarm)), \(subtitle)")
            .accessibilityHint("Edits the alarm")

            Toggle(alarm.title, isOn: Binding(get: { alarm.isEnabled }, set: { service.setEnabled(alarm.id, $0) }))
                .labelsHidden()
                .tint(.orange)
                // Larger for a display tapped at arm's length, growing inward.
                // The switch draws a little past its frame, so it keeps clear of
                // the list's edge, which clips it.
                .scaleEffect(1.3, anchor: .trailing)
                .padding(.trailing, Theme.Spacing.s)
                .accessibilityLabel("\(AlarmFormat.time(alarm)) alarm")
        }
        .padding(.vertical, Theme.Spacing.m)
        .animation(Theme.Motion.standard, value: alarm.isEnabled)
    }

    /// "Wake Up, weekdays", or when a snoozed alarm rings again.
    private var subtitle: String {
        if service.isSnoozed(alarm.id), let end = service.upcoming[alarm.id] {
            return "\(alarm.title), snoozed until \(end.formatted(date: .omitted, time: .shortened))"
        }
        return AlarmFormat.subtitle(alarm)
    }
}
