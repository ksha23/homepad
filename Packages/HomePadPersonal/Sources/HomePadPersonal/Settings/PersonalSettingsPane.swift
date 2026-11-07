import HomePadCore
import HomePadUI
import SwiftUI

/// Settings, Personal Info: weather, who owns which calendar (with every
/// calendar on the iPad and why it shows or not), reminders, world clock,
/// photo sources and whose each Find My device is. Admin only, because it
/// controls privacy.
struct PersonalSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            WeatherSettingsSection()
            CalendarMappingSection(kind: .events)
            AllCalendarsSection()
            CalendarMappingSection(kind: .reminders)
            RemindersSettingsSection()
            WorldClockSettingsSection()
            PhotoSourcesSection()
            FindMySettingsSection()
            Section {
                Toggle("Show Demo Data", isOn: settings.binding(PersonalSettings.demoData))
            } footer: {
                Text("Demo calendars, reminders, photos and Find My devices stand in for this iPad's own. Useful in the simulator, which has no accounts.")
            }
        }
        .navigationTitle("Personal Info")
    }
}
