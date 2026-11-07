import AVFoundation
import HomePadCore
import HomePadUI
import SwiftUI

/// How answers sound: on or off, which voice, and how fast.
struct VoiceSettingsSection: View {
    @Environment(AppServices.self) private var services
    @State private var personalVoice = VoiceCatalog.personalVoiceStatus

    var body: some View {
        let settings = services.settings
        let hasOpenAIKey = services.keychain.has(ProviderCatalog.openAI.keychainAccount)
        let engine = settings[AssistantSettings.voiceEngine]
        let speech = (services.assistant as? AssistantRuntime)?.speech
        Section {
            Toggle("Speak Answers", isOn: settings.binding(AssistantSettings.speakResponses))
            LabeledSegmentedPicker(
                "Voices", selection: settings.binding(AssistantSettings.voiceEngine),
                options: VoiceEngine.allCases.filter { $0 != .openAI || hasOpenAIKey }
            ) { $0.displayName }
            .onChange(of: engine) { speech?.prepareNaturalVoice() }
            switch engine {
            case .openAI where hasOpenAIKey:
                Picker("Voice", selection: settings.binding(AssistantSettings.cloudVoice)) {
                    ForEach(CloudVoice.allCases) { Text($0.displayName).tag($0) }
                }
            case .natural:
                Picker("Voice", selection: settings.binding(AssistantSettings.naturalVoice)) {
                    ForEach(NaturalVoice.allCases) { Text($0.displayName).tag($0) }
                }
                if let speech { NaturalVoiceStatus(speech: speech) }
            default:
                Picker("Voice", selection: settings.binding(AssistantSettings.voiceIdentifier)) {
                    Text("Automatic").tag("")
                    ForEach(VoiceCatalog.options()) { option in
                        Text("\(option.name) (\(option.detail))").tag(option.id)
                    }
                }
                if personalVoice == .notDetermined {
                    Button("Use My Personal Voice") {
                        Task {
                            _ = await VoiceCatalog.requestPersonalVoice()
                            personalVoice = VoiceCatalog.personalVoiceStatus
                        }
                    }
                }
            }
            LabeledSegmentedPicker(
                "Speaking Rate", selection: settings.binding(AssistantSettings.speakingRate), options: SpeakingRate.allCases
            ) { $0.displayName }
            Button("Play Sample") {
                speech?.enqueue("Hi, I'm HomePad. This is how I'll sound when I answer.")
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(footer(engine))
        }
    }

    private func footer(_ engine: VoiceEngine) -> String {
        switch engine {
        case .system:
            "Apple voices are private and work offline. Automatic uses the best one on this iPad. Download Premium voices in the Settings app under Accessibility, Read & Speak, Voices."
        case .natural:
            "Natural is a neural voice that runs on this iPad: private and offline after a one-time 330 MB download. The Apple voice speaks until it is ready."
        case .openAI:
            "OpenAI voices send answers to OpenAI to be read aloud."
        }
    }
}

/// Where the Natural voice stands: downloading, getting ready, or ready.
private struct NaturalVoiceStatus: View {
    let speech: SpeechController

    var body: some View {
        #if targetEnvironment(simulator)
        Label("The Natural voice needs an iPad. The simulator uses the Apple voice.", systemImage: "info.circle")
            .foregroundStyle(.secondary)
        #else
        switch speech.naturalModel.state {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Downloading the Natural voice, \(Int(fraction * 100))%")
                ProgressView(value: fraction)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(message).foregroundStyle(.secondary)
                Button("Try Again") { speech.prepareNaturalVoice() }
            }
        case .missing:
            Button("Download Natural Voice (330 MB)") { speech.prepareNaturalVoice() }
        case .ready:
            if speech.isNaturalLoaded {
                Label("Natural voice ready", systemImage: "checkmark.circle.fill")
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView()
                    Text("Getting the Natural voice ready")
                }
            }
        }
        #endif
    }
}
