import HomePadCore
import HomePadUI
import SwiftUI

/// The wake phrase and how long HomePad waits after you stop talking.
struct ListeningSettingsSection: View {
    @Environment(AppServices.self) private var services

    /// A few phrases that recognize reliably.
    static let wakePhrases = ["Hey HomePad", "HomePad", "Okay HomePad"]

    var body: some View {
        let settings = services.settings
        Section {
            Toggle("Listen for \u{201C}\(settings[CoreSettings.wakePhrase])\u{201D}", isOn: wakeBinding)
            Picker("Wake Phrase", selection: settings.binding(CoreSettings.wakePhrase)) {
                ForEach(Self.wakePhrases, id: \.self) { Text($0).tag($0) }
            }
            if let runtime = services.assistant as? AssistantRuntime {
                LabeledContent("Status", value: status(runtime.wake))
            }
            LabeledSegmentedPicker(
                "Wait After I Speak", selection: settings.binding(AssistantSettings.listeningPatience), options: ListeningPatience.allCases
            ) { $0.displayName }
            Toggle("Listen for Follow-Ups", isOn: settings.binding(AssistantSettings.followUpListening))
        } header: {
            Text("Listening")
        } footer: {
            Text("Speech is recognized on this iPad. The wake phrase pauses when nobody is around at night, while music plays to AirPlay speakers, and when the microphone is off in Control Center.")
        }
    }

    /// Turning the wake phrase on asks for the microphone if needed.
    private var wakeBinding: Binding<Bool> {
        Binding(get: { services.settings[CoreSettings.wakeWordEnabled] }, set: { isOn in
            services.settings[CoreSettings.wakeWordEnabled] = isOn
            if isOn { Task { _ = await SpeechPermissions.request() } }
        })
    }

    private func status(_ monitor: WakeWordMonitor) -> String {
        switch monitor.state {
        case .waiting: "Listening"
        case .capturing: "Hearing a request"
        case .off(let reason): reason
        }
    }
}
