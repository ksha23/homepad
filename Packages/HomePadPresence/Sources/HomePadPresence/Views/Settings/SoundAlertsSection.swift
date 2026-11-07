import HomePadCore
import HomePadUI
import SwiftUI

/// Sound alert switches: master toggle, sensitivity and which sounds alert.
struct SoundAlertsSection: View {
    let sounds: SoundAlertService
    @Environment(AppServices.self) private var services

    var body: some View {
        let settings = services.settings
        Section {
            Toggle("Sound Alerts", isOn: settings.binding(CoreSettings.soundAlertsEnabled))
            if settings[CoreSettings.soundAlertsEnabled] {
                LabeledSegmentedPicker(
                    "Sensitivity", selection: settings.binding(PresenceSettings.soundSensitivity),
                    options: SensingSensitivity.allCases, optionTitle: \.title
                )
                ForEach(SoundAlertKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
                Button("Test Smoke Alarm Alert") { sounds.simulate(.smokeAlarm) }
            }
            if let status = sounds.statusMessage, settings[CoreSettings.soundAlertsEnabled] {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Sound Alerts")
        } footer: {
            Text("Listens on this iPad with Apple's sound classifier and never records. Carbon monoxide alarms have no separate sound model and are recognized as smoke alarms when they are recognized at all. Do not rely on HomePad in an emergency.")
        }
    }

    private func binding(for kind: SoundAlertKind) -> Binding<Bool> {
        let settings = services.settings
        return Binding(
            get: { settings[PresenceSettings.alertSounds].contains(kind.rawValue) },
            set: { enabled in
                var kinds = Set(settings[PresenceSettings.alertSounds])
                if enabled { kinds.insert(kind.rawValue) } else { kinds.remove(kind.rawValue) }
                settings[PresenceSettings.alertSounds] = SoundAlertKind.allCases.map(\.rawValue).filter(kinds.contains)
            }
        )
    }
}
