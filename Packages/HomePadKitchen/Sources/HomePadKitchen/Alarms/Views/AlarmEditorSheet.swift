import HomePadCore
import HomePadUI
import SwiftUI

/// Add or change an alarm: the time on wheels, the days it repeats, a label
/// and snooze, as in the Clock app. Add (or Save) is the sheet's one action,
/// and an alarm being changed can be deleted at the bottom.
struct AlarmEditorSheet: View {
    @Environment(AlarmService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: HomeAlarm
    private let isNew: Bool

    init(draft: AlarmDraft) {
        _alarm = State(initialValue: draft.alarm)
        isNew = draft.isNew
    }

    var body: some View {
        SheetScreen(isNew ? "New Alarm" : "Edit Alarm") {
            GlassCapsuleButton(isNew ? "Add" : "Save", isProminent: true, action: save)
        } content: {
            Form {
                Section {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                Section("Repeat") {
                    WeekdayPicker(weekdays: $alarm.weekdays)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                Section {
                    TextField("Label", text: $alarm.label, prompt: Text("Alarm"))
                    Toggle("Snooze", isOn: $alarm.allowsSnooze)
                        .tint(.orange)
                } footer: {
                    Text("Snooze rings again after nine minutes.")
                }
                if !isNew {
                    Section {
                        Button("Delete Alarm", role: .destructive, action: delete)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        // Page-sized, so the wheels, the days, the label and snooze all fit
        // without scrolling.
        .presentationSizing(.page)
    }

    /// The wheels' date, today at the alarm's time.
    private var time: Binding<Date> {
        Binding {
            AlarmFormat.date(of: alarm)
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            alarm.hour = parts.hour ?? alarm.hour
            alarm.minute = parts.minute ?? alarm.minute
        }
    }

    private func save() {
        var saved = alarm
        // Setting an alarm means it should ring.
        saved.isEnabled = true
        if isNew { service.add(saved) } else { service.update(saved) }
        dismiss()
    }

    private func delete() {
        service.delete(alarm.id)
        dismiss()
    }
}
