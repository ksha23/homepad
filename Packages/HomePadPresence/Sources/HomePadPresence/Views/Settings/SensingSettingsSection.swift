import HomePadCore
import HomePadUI
import SwiftUI

/// Camera, sensitivity and gesture switches.
struct SensingSettingsSection: View {
    let presence: LivePresenceService
    @Environment(AppServices.self) private var services

    var body: some View {
        let settings = services.settings
        Section {
            Toggle("Camera", isOn: settings.binding(CoreSettings.cameraEnabled))
            if presence.hasTrueDepth {
                Toggle("Use Face ID Camera", isOn: settings.binding(PresenceSettings.useTrueDepth))
            }
            LabeledSegmentedPicker(
                "Sensitivity", selection: settings.binding(PresenceSettings.sensitivity),
                options: SensingSensitivity.allCases, optionTitle: \.title
            )
            Toggle("Share Motion With Faces", isOn: settings.binding(PresenceSettings.motionEvents))
        } header: {
            Text("Presence Sensing")
        } footer: {
            Text(sensingFooter)
        }

        Section {
            Toggle("Hand Gestures", isOn: settings.binding(CoreSettings.handGesturesEnabled))
            Toggle("Palm Plays and Pauses Music", isOn: settings.binding(CoreSettings.palmControlsMusic))
                .disabled(!settings[CoreSettings.handGesturesEnabled])
            Toggle("AirPods Head Gestures", isOn: settings.binding(PresenceSettings.headGestures))
            if let reason = presence.headGestures.unavailableReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            } else if settings[PresenceSettings.headGestures] {
                LabeledContent("AirPods", value: presence.headGestures.isHeadphonesConnected ? "Connected" : "Not connected")
            }
        } header: {
            Text("Gestures")
        } footer: {
            Text("Hold an open palm still toward the iPad for a moment to stop a ringing timer, and, with Palm Plays and Pauses Music on, to play or pause music. With AirPods in, nod to answer yes or shake your head to answer no.")
        }
    }

    private var sensingFooter: String {
        if presence.hasTrueDepth {
            return "The Face ID camera measures distance in the dark using infrared light. When nobody is around it checks a few times a second to save power. Everything is processed on this iPad."
        }
        return "The front camera notices people and estimates distance from face size. When nobody is around it checks a few times a second to save power. Everything is processed on this iPad."
    }
}
