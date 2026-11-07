import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > Kiosk & Display: Guided Access, always-on tips, timing, night
/// schedule, brightness per condition, text size and screen care.
struct KioskSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(KioskController.self) private var kiosk: KioskController?
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?

    var body: some View {
        Form {
            KioskStatusSection()
            GuidedAccessSection()
            KioskTipsSection()
            timingSection
            nightSection
            brightnessSection
            displaySection
        }
        .onChange(of: settings.revision) { kiosk?.tick() }
    }

    private var timingSection: some View {
        Section {
            Picker("Back to Face After", selection: settings.binding(CoreSettings.returnToFaceAfter)) {
                ForEach([15.0, 30, 60, 120, 300], id: \.self) { Text(Self.duration(seconds: $0)).tag($0) }
            }
            Picker("Dim When Nobody Is Around For", selection: settings.binding(ShellSettings.dimAfterMinutes)) {
                ForEach([1.0, 2, 5, 10], id: \.self) { Text(Self.duration(seconds: $0 * 60)).tag($0) }
            }
            Picker("Sleep When Nobody Is Around For", selection: settings.binding(CoreSettings.sleepAfterMinutes)) {
                ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text(Self.duration(seconds: $0 * 60)).tag($0) }
                Text("Never").tag(0.0)
            }
            Toggle("Keep Screen On", isOn: settings.binding(ShellSettings.keepScreenOn))
        } header: {
            Text("Timing")
        } footer: {
            Text("HomePad returns to the face after you stop touching it, dims when nobody is near, and goes dark when nobody has been around for a while. Touch, someone walking up, a doorbell or a timer wakes it.")
        }
    }

    private var nightSection: some View {
        Section {
            Toggle("Automatic Night Mode", isOn: settings.binding(CoreSettings.nightModeAutomatic))
            DatePicker("Night Starts", selection: scheduleBinding(\.startMinute), displayedComponents: .hourAndMinute)
            DatePicker("Night Ends", selection: scheduleBinding(\.endMinute), displayedComponents: .hourAndMinute)
            Toggle("Night Mode Now", isOn: settings.binding(ShellSettings.nightModeForced))
        } header: {
            Text("Night")
        } footer: {
            Text("Night mode turns the screen a dim red that is easy on the eyes in the dark. It turns on during these hours, unless the room is lit.")
        }
    }

    private var brightnessSection: some View {
        Section {
            Toggle("Use iPad Auto-Brightness", isOn: settings.binding(ShellSettings.followSystemBrightness))
            if settings[ShellSettings.followSystemBrightness] {
                brightnessSlider("Nobody Nearby", condition: .dimmed)
                brightnessSlider("Night", condition: .night)
            } else {
                brightnessSlider("In Use", condition: .active)
                brightnessSlider("Face", condition: .ambient)
                brightnessSlider("Nobody Nearby", condition: .dimmed)
                brightnessSlider("Night", condition: .night)
                brightnessSlider("Sleeping", condition: .sleeping)
                Toggle("Match Room Light", isOn: settings.binding(ShellSettings.adaptToRoomLight))
            }
        } header: {
            Text("Brightness")
        } footer: {
            if settings[ShellSettings.followSystemBrightness] {
                Text("The iPad's own light sensor sets the brightness while someone is using HomePad or looking at the face. HomePad only dims the screen when nobody is nearby, at night and while sleeping, then hands it back. Turn on Auto-Brightness in Settings, Accessibility, Display & Text Size.")
            } else {
                Text("HomePad sets the brightness itself, changing slowly between these levels. Match Room Light uses the front camera to make the screen brighter in a sunny room and dimmer in a dark one.")
            }
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Appearance", selection: settings.binding(ShellSettings.appearance)) {
                ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Text Size", selection: settings.binding(ShellSettings.textSize)) {
                ForEach(TextSizeChoice.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show Close Buttons", isOn: settings.binding(ShellSettings.showsCloseButton))
            Toggle("Burn-In Protection", isOn: settings.binding(ShellSettings.burnInProtection))
            if settings[ShellSettings.burnInProtection] {
                Picker("Shift Amount", selection: settings.binding(ShellSettings.burnInAmplitude)) {
                    Text("Subtle").tag(4.0)
                    Text("Standard").tag(8.0)
                    Text("Strong").tag(12.0)
                }
            }
            Toggle("Warn When Not Charging", isOn: settings.binding(ShellSettings.chargingWarning))
            if let navigator {
                Button("Run Setup Again") { navigator.isShowingOnboarding = true }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Swipe up from the bottom edge to close an app. Show Close Buttons adds a close button to the top right of every app as well. Burn-in protection slowly moves the face a few points so the OLED screens on recent iPad Pro models never show the same pixels for hours.")
        }
    }

    private func brightnessSlider(_ title: String, condition: DisplayCondition) -> some View {
        let binding = Binding<Double>(
            get: { settings[ShellSettings.brightnessLevels][condition] },
            set: { value in
                var levels = settings[ShellSettings.brightnessLevels]
                levels[condition] = value
                settings[ShellSettings.brightnessLevels] = levels
            }
        )
        return LabeledContent {
            Slider(value: binding, in: 0...1)
                .frame(maxWidth: 320)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(binding.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleBinding(_ keyPath: WritableKeyPath<NightSchedule, Int>) -> Binding<Date> {
        Binding(
            get: { NightSchedule.date(forMinute: settings[ShellSettings.nightSchedule][keyPath: keyPath]) },
            set: { date in
                var schedule = settings[ShellSettings.nightSchedule]
                schedule[keyPath: keyPath] = NightSchedule.minute(for: date)
                settings[ShellSettings.nightSchedule] = schedule
            }
        )
    }

    private static func duration(seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
