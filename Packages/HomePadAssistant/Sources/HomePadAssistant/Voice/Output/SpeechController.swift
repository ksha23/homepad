import Foundation
import HomePadCore
import Observation

/// Speaks answer sentences one after another as they stream in, and can be
/// stopped at once. The Apple voice has its own system audio session. The
/// Natural and cloud voices play through HomePad's, so they claim `.playback`.
@MainActor
@Observable
final class SpeechController {
    private(set) var isSpeaking = false
    /// The sentence being spoken, used to ignore HomePad's own voice when listening for "stop".
    private(set) var currentSentence = ""

    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var active: (any SpeechOutput)?
    @ObservationIgnored private let system = SystemSpeechOutput()
    /// The Natural voice's model file. Downloads only once that voice is chosen.
    @ObservationIgnored let naturalModel = NaturalVoiceModel()
    @ObservationIgnored private let kokoro = KokoroEngine()
    @ObservationIgnored private lazy var natural = NaturalSpeechOutput(engine: kokoro)
    /// True once Kokoro is loaded and warmed up. Until then the Apple voice speaks.
    private(set) var isNaturalLoaded = false
    @ObservationIgnored private var naturalLoad: Task<Void, Never>?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let audioSession: AudioSessionCoordinator
    /// OpenAI address and key when OpenAI voices are chosen and a key exists.
    @ObservationIgnored private let cloudCredentials: @MainActor () -> (URL, String)?
    private static let owner = "assistant.speech"

    init(settings: SettingsStore, audioSession: AudioSessionCoordinator, cloudCredentials: @escaping @MainActor () -> (URL, String)?) {
        self.settings = settings
        self.audioSession = audioSession
        self.cloudCredentials = cloudCredentials
    }

    /// Queues a sentence. Answer Markdown (the bold key facts) is dropped, so no voice reads asterisks.
    func enqueue(_ text: String) {
        let trimmed = AnswerMarkdown.plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.append(trimmed)
        // The Natural voice starts on each sentence as it arrives, so it is ready
        // by the time the one before it has been spoken.
        naturalIfReady()?.prepare(trimmed)
        guard worker == nil else { return }
        // Speaking from the moment a sentence is queued. Set only once the task
        // ran, a one-sentence answer looked silent to the caller, which then
        // listened for a follow-up and stopped the answer before it was said.
        isSpeaking = true
        worker = Task { [weak self] in await self?.drain() }
    }

    /// Stops talking now and drops anything queued.
    func stop() {
        queue.removeAll()
        worker?.cancel()
        active?.stop()
        // Sentences made ahead of time are dropped too.
        if isNaturalLoaded { natural.stop() }
    }

    /// Waits until everything queued has been spoken or stopped.
    func waitUntilDone() async {
        await worker?.value
    }

    private func drain() async {
        isSpeaking = true
        var claimed = false
        while !queue.isEmpty, !Task.isCancelled {
            let sentence = queue.removeFirst()
            currentSentence = sentence
            let output = makeOutput()
            if output !== system, !claimed {
                audioSession.claim(.playback, owner: Self.owner)
                claimed = true
            }
            AssistantTrace.trace.log("speaking with \(output === system ? "the Apple voice" : "HomePad's audio"): \"\(sentence)\"")
            active = output
            do {
                try await output.speak(sentence)
            } catch {
                // A cloud voice failure falls back to the on-device voice for this sentence.
                if output !== system, !Task.isCancelled { try? await system.speak(sentence) }
            }
        }
        active = nil
        currentSentence = ""
        isSpeaking = false
        if claimed { audioSession.release(owner: Self.owner) }
        AssistantTrace.trace.log("speaking done")
        worker = nil
    }

    /// Downloads and loads the Natural voice when it is chosen. Safe to call often.
    /// The simulator has no GPU for it and keeps the Apple voice.
    func prepareNaturalVoice() {
        #if !targetEnvironment(simulator)
        guard settings[AssistantSettings.voiceEngine] == .natural, !isNaturalLoaded, naturalLoad == nil else { return }
        naturalModel.onReady = { [weak self] in self?.prepareNaturalVoice() }
        guard naturalModel.state == .ready else {
            naturalModel.downloadIfNeeded()
            return
        }
        let modelURL = naturalModel.fileURL
        naturalLoad = Task { [weak self, kokoro] in
            let loaded = (try? await kokoro.load(modelURL: modelURL)) != nil
            self?.isNaturalLoaded = loaded
            self?.naturalLoad = nil
        }
        #endif
    }

    /// The Natural voice, set to the chosen voice and rate, when it is chosen and loaded.
    private func naturalIfReady() -> NaturalSpeechOutput? {
        guard settings[AssistantSettings.voiceEngine] == .natural else { return nil }
        guard isNaturalLoaded else {
            prepareNaturalVoice()
            return nil
        }
        natural.voice = settings[AssistantSettings.naturalVoice]
        natural.rate = settings[AssistantSettings.speakingRate]
        return natural
    }

    private func makeOutput() -> any SpeechOutput {
        if settings[AssistantSettings.voiceEngine] == .openAI, let (url, key) = cloudCredentials() {
            return CloudSpeechOutput(baseURL: url, apiKey: key, voice: settings[AssistantSettings.cloudVoice])
        }
        if let natural = naturalIfReady() { return natural }
        system.voiceIdentifier = settings[AssistantSettings.voiceIdentifier]
        system.rate = settings[AssistantSettings.speakingRate]
        return system
    }
}
