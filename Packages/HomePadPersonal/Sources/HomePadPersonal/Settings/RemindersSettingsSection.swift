import HomePadCore
import SwiftUI

/// The default reminders list that voice requests and other modules add to.
struct RemindersSettingsSection: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if calendar.hasReminderAccess {
            Section {
                Picker("Default List", selection: settings.binding(PersonalSettings.defaultReminderList)) {
                    ForEach(listNames, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text("\"Add milk\" and items from recipes go to this list. HomePad creates it and shares it with everyone if it does not exist yet.")
            }
        }
    }

    private var listNames: [String] {
        var names = calendar.allReminderLists.map(\.title)
        let current = settings[PersonalSettings.defaultReminderList]
        if !names.contains(current) { names.insert(current, at: 0) }
        return names
    }
}
