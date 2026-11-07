import HomePadCore
import HomePadUI
import SwiftUI

// Form sections for Security Camera mode. The Security Camera screen and the
// Camera Lab Settings pane both show them, so the two never drift apart.

/// The on and off switch, status and the one-camera explanation.
struct SecurityStatusSection: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        let security = lab.security
        Section {
            Toggle(isOn: Binding(get: { security.isEnabled }, set: { security.setEnabled($0) })) {
                Label("Security Camera", systemImage: "video.badge.waveform")
            }
            LabeledContent("Status", value: statusText)
            if let problem = security.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let last = security.lastAlertAt {
                LabeledContent("Last Motion") {
                    Text(last, format: .relative(presentation: .named))
                }
            }
        } footer: {
            Text("iOS lets an app use one camera at a time, so presence sensing pauses while Security Camera watches. Use a schedule to keep that time short.")
        }
    }

    private var statusText: String {
        let security = lab.security
        if !security.isEnabled { return "Off" }
        if security.isWatching { return "Watching with the \(security.camera.title.lowercased())" }
        return "Waiting for the schedule"
    }
}

/// Schedule presets and which camera watches.
struct SecurityScheduleSection: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab

    var body: some View {
        Section {
            Picker("Schedule", selection: services.settings.binding(CameraLabSettings.securitySchedule)) {
                ForEach(SecuritySchedule.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            Picker("Camera", selection: services.settings.binding(CameraLabSettings.securityCamera)) {
                ForEach(CameraPosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("\(lab.security.schedule.detail) The back camera is recommended because it leaves the front of the iPad free for faces.")
        }
    }
}

/// Motion sensitivity, person confirmation and the snapshot buffer.
struct SecurityDetectionSection: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var confirmClear = false

    var body: some View {
        let sensitivity = services.settings[CameraLabSettings.securitySensitivity]
        Section {
            Picker("Sensitivity", selection: services.settings.binding(CameraLabSettings.securitySensitivity)) {
                ForEach(MotionSensitivity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            Toggle("Only Alert for People", isOn: services.settings.binding(CameraLabSettings.securityRequirePerson))
            Picker("Keep Snapshots", selection: services.settings.binding(CameraLabSettings.securitySnapshotLimit)) {
                ForEach(CameraLabSettings.snapshotLimitChoices, id: \.self) { Text("\($0)").tag($0) }
            }
            Button("Delete All Snapshots", role: .destructive) { confirmClear = true }
                .disabled(lab.security.snapshots.isEmpty)
                .confirmationDialog("Delete all motion snapshots?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Delete Snapshots", role: .destructive) { lab.security.clearSnapshots() }
                }
        } header: {
            Text("Detection")
        } footer: {
            Text("\(sensitivity.detail) Person checks use Vision on this iPad to skip shadows, curtains and pets. Snapshots stay on this iPad.")
        }
    }
}

/// The LAN stream: port, token and the exact Home Assistant values.
struct SecurityStreamSection: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var confirmNewToken = false

    var body: some View {
        let security = lab.security
        Section {
            LabeledContent("Server", value: serverText)
            Picker("Port", selection: services.settings.binding(CameraLabSettings.securityPort)) {
                ForEach(CameraLabSettings.portChoices, id: \.self) { Text(String($0)).tag($0) }
            }
            ForEach(security.homeAssistantSetup.fields, id: \.label) { field in
                if field.value.hasPrefix("http") {
                    CopyableValueRow(label: field.label, value: field.value)
                } else {
                    LabeledContent(field.label, value: field.value)
                }
            }
            Button("Make New Token") { confirmNewToken = true }
                .confirmationDialog("Make a new stream token?", isPresented: $confirmNewToken, titleVisibility: .visible) {
                    Button("Make New Token", role: .destructive) { security.regenerateToken() }
                } message: {
                    Text("Anyone using the old URLs, including Home Assistant, is disconnected until you paste the new ones.")
                }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("In Home Assistant open Settings, Devices and services, Add integration, and choose MJPEG IP Camera. Enter the values above. Give this iPad a fixed address in your router so the URLs keep working. The token in the URL is the password, so keep it private.")
        }
    }

    private var serverText: String {
        switch lab.security.serverState {
        case .stopped: "Off"
        case .listening(let port): "Listening on port \(port)"
        case .failed(let message): message
        }
    }
}

/// The optional Home Assistant webhook called on confirmed motion.
struct SecurityWebhookSection: View {
    @Environment(CameraLab.self) private var lab
    @State private var text = ""

    var body: some View {
        Section {
            TextField("https://homeassistant.local:8123/api/webhook/...", text: $text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(save)
            if !text.isEmpty, MotionWebhook.validatedURL(text) == nil {
                Label("Enter a full http or https address.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Motion Webhook")
        } footer: {
            Text("Optional. Make an automation with a Webhook trigger in Home Assistant and paste its URL. HomePad posts person_detected, changed_fraction, time and snapshot_url when motion is confirmed.")
        }
        .onAppear { text = lab.security.webhookURL }
        .onDisappear(perform: save)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || MotionWebhook.validatedURL(trimmed) != nil else { return }
        lab.security.webhookURL = trimmed
    }
}
