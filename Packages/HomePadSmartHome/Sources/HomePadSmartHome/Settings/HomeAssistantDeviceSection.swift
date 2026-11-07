import HomePadCore
import HomePadUI
import SwiftUI

/// This HomePad as a device in Home Assistant: the switch (off by default), the
/// name it goes by, what was registered, Remove from Home Assistant, and every
/// sensor it sends with its value right now, so nothing is sent unseen.
struct HomeAssistantDeviceSection: View {
    static let anchorID = "homeAssistantDevice"

    @Environment(HomeAssistantDevice.self) private var device
    @State private var confirmsRemoval = false

    /// A registered look for screenshots (`-HomePadSmartHomeDevicePreview YES`).
    private let preview = SmartHomeLaunchOptions.atLaunch.devicePreview

    private var isEnabled: Binding<Bool> {
        Binding(get: { preview || device.isEnabled }, set: { device.isEnabled = $0 })
    }

    private var status: HomeAssistantDevice.Status { preview ? .active : device.status }

    private var registration: MobileAppRegistration.Stored? {
        guard preview else { return device.registration }
        return MobileAppRegistration.Stored(webhookID: "", instanceURL: "", deviceName: device.deviceName,
                                            appVersion: "", registeredAt: Date().addingTimeInterval(-3600))
    }

    var body: some View {
        Section {
            Toggle("Show This HomePad in Home Assistant", isOn: isEnabled)
                .disabled(!preview && device.backend.configuration == nil && !device.isEnabled)
            LabeledContent("Name", value: device.deviceName)
            LabeledContent("Status") {
                Text(status.summary)
                    .foregroundStyle(status == .active ? .green : .secondary)
            }
            if let registration {
                LabeledContent("Registered") {
                    Text(registration.registeredAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Commands") {
                    Text(verbatim: "notify." + MobileAppNaming.notifyService(deviceName: registration.deviceName))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            if let problem = device.commandsProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let message = device.removalMessage {
                Label(message, systemImage: "info.circle")
            }
            if registration != nil || device.isEnabled {
                Button(device.isRemoving ? "Removing" : "Remove from Home Assistant", systemImage: "minus.circle",
                       role: .destructive) { confirmsRemoval = true }
                    .disabled(device.isRemoving || preview)
            }
        } header: {
            Text("This HomePad in Home Assistant")
        } footer: {
            Text("Home Assistant sees this HomePad as a device with the sensors below, and its automations can send it commands and messages. The name follows this HomePad's room in Devices & Sharing.")
        }
        .id(Self.anchorID)
        .confirmationDialog("Remove \(registration?.deviceName ?? device.deviceName) from Home Assistant?",
                            isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await device.removeFromHomeAssistant() } }
        } message: {
            Text("Its sensors stop and Home Assistant can no longer send it commands. Removing the device needs an administrator's token.")
        }
        sensorsSection
    }

    /// Every sensor with what Home Assistant gets right now.
    private var sensorsSection: some View {
        let inputs = device.readInputs()
        let name = registration?.deviceName ?? device.deviceName
        return Section {
            ForEach(inputs.states, id: \.sensor) { state in
                LabeledContent {
                    Text(Self.display(state))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.sensor.name)
                        Text(verbatim: Self.entityID(of: state.sensor, deviceName: name))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("What Home Assistant Sees")
        } footer: {
            Text("Only these values go to Home Assistant, as they change and at most every \(Int(MobileAppReportThrottle.standardInterval)) seconds. Faces, face data, photos, the camera and the microphone never leave the iPad. Who is recognized is a name, or Guest.")
        }
    }

    /// The entity ID Home Assistant gives the sensor unless it is taken.
    static func entityID(of sensor: MobileAppSensor, deviceName: String) -> String {
        "\(sensor.type).\(HAPlaySoundCall.slug(deviceName))_\(HAPlaySoundCall.slug(sensor.name))"
    }

    /// A value as Settings shows it.
    static func display(_ state: MobileAppSensorState) -> String {
        switch state.state {
        case .bool(let on):
            switch state.sensor {
            case .presence: return on ? "Detected" : "Clear"
            case .charging: return on ? "On Power" : "On Battery"
            default: return on ? "On" : "Off"
            }
        case .number(let value):
            let number = value.formatted(.number.precision(.fractionLength(0...1)))
            return state.sensor.unit.map { $0 == "%" ? number + "%" : "\(number) \($0)" } ?? number
        case .string(let text):
            if state.state == MobileAppSensorState.unavailable { return "Unknown" }
            // Machine states such as "home_screen" read as "Home Screen".
            guard text == text.lowercased() else { return text }
            return text.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        default:
            return "Unknown"
        }
    }
}
