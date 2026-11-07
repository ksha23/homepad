import HomePadCore
import HomePadUI
import SwiftUI

/// Which doorbell rings, which camera shows and which lock the overlay unlocks.
struct DoorbellSettingsSection: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services

    /// Picked on any HomePad, so read as this HomePad knows them.
    private var doorbell: Binding<DoorbellSettings> {
        Binding(get: { service.doorbell }, set: { service.doorbell = $0 })
    }

    /// Anything that could be a doorbell button: doorbells, on and off sensors and switches.
    private var triggerCandidates: [HomeAccessory] {
        service.allAccessories.filter { accessory in
            switch accessory.kind {
            case .doorbell, .switchOutlet: true
            case .sensor: accessory.state.isActive != nil
            default: false
            }
        }
    }

    var body: some View {
        Section {
            Picker("Doorbell", selection: doorbell.triggerID) {
                Text("Automatic").tag(String?.none)
                ForEach(triggerCandidates) { Text(label($0.name, $0.room)).tag(Optional($0.id)) }
            }
            Picker("Camera", selection: doorbell.cameraID) {
                Text("Automatic").tag(String?.none)
                ForEach(service.allCameras) { Text(label($0.name, $0.room)).tag(Optional($0.id)) }
            }
            Picker("Lock to Unlock", selection: doorbell.lockID) {
                Text("Automatic").tag(String?.none)
                ForEach(service.allAccessories.filter { $0.kind == .lock }) { Text(label($0.name, $0.room)).tag(Optional($0.id)) }
            }
            Picker("Close After", selection: doorbell.autoDismissSeconds) {
                ForEach(DoorbellSettings.dismissChoices, id: \.self) { seconds in
                    Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))).tag(seconds)
                }
            }
            Toggle("Chime", isOn: services.settings.binding(SmartHomeSettings.doorbellChime))
            Toggle("Quiet in Night Mode", isOn: services.settings.binding(SmartHomeSettings.doorbellChimeQuietAtNight))
                .disabled(!services.settings[SmartHomeSettings.doorbellChime])
            Button("Test Doorbell", systemImage: "bell.badge") {
                service.doorbellRang(cameraID: nil)
            }
        } header: {
            Text("Doorbell")
        } footer: {
            Text("Automatic uses doorbell events from Home Assistant and Apple Home, the camera on the same device, and a lock in the same room. The chime plays on this HomePad and stays silent during Quiet Hours.")
        }
    }

    private func label(_ name: String, _ room: String?) -> String {
        room.map { "\(name), \($0)" } ?? name
    }
}
