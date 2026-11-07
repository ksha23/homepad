import Foundation
import HomePadCore
import Observation

/// Listens on device for the wake phrase ("Hey HomePad") and captures the
/// request that follows. It only runs on a HomePad (`AppRole`), when the person turned it on, the
/// microphone is allowed without a prompt, someone may be around, and no
/// AirPlay music holds the long-form audio session.
@MainActor
@Observable
final class WakeWordMonitor {
    enum State: Equatable {
        case off(String)
        case waiting
        case capturing
    }

    private(set) var state: State = .off("Starting")

    /// Phrase heard. Show the listening overlay.
    @ObservationIgnored var onWake: (() -> Void)?
    /// Live text of the request after the phrase.
    @ObservationIgnored var onPartial: ((String) -> Void)?
    /// The finished request (may be empty when the person only said the phrase).
    @ObservationIgnored var onCommand: ((String) -> Void)?
    /// True while a conversation owns the microphone.
    @ObservationIgnored var isBusy: () -> Bool = { false }

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var engine: (any TranscriptionEngine)?
    @ObservationIgnored private var detector: EndOfSpeechDetector?
    @ObservationIgnored private var command = ""
    /// The wake phrase setting, read on each check rather than on every
    /// partial transcript, which arrive several times a second.
    @ObservationIgnored private var phrase = "Hey HomePad"
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    /// Re-checks the conditions every couple of seconds, and ticks end-of-speech while capturing.
    func begin() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(for: .milliseconds(self?.state == .capturing ? 150 : 2000))
            }
        }
    }

    /// Why the wake phrase is paused, or nil when it may listen.
    func pauseReason() -> String? {
        guard let services else { return "Unavailable" }
        // The wake phrase is the HomePad's. A companion phone or Mac never listens for it.
        if AppRole.current != .homePad { return "Only on a HomePad" }
        let settings = services.settings
        if !settings[CoreSettings.wakeWordEnabled] { return "Off" }
        if !settings[CoreSettings.microphoneEnabled] { return "Microphone is off" }
        if !SpeechPermissions.grantedWithoutPrompt { return "Needs microphone permission" }
        if isBusy() { return "Paused during a conversation" }
        if services.audioSession.mode == .longFormPlayback { return "Paused while music plays to AirPlay speakers" }
        if services.displayCondition == .sleeping, !services.presence.snapshot.isSomeonePresent {
            return "Paused while nobody is around"
        }
        return nil
    }

    /// Releases the microphone right away, for push-to-talk. The loop restarts it when allowed.
    func suspend() async {
        guard engine != nil else { return }
        await stopEngine()
        state = .off("Paused during a conversation")
    }

    private func evaluate() async {
        if state == .capturing {
            finishCaptureIfDone()
            return
        }
        if let reason = pauseReason() {
            if engine != nil { await stopEngine() }
            AssistantTrace.trace.logIfChanged("wake", "wake phrase paused: \(reason)")
            state = .off(reason)
        } else if let services {
            phrase = services.settings[CoreSettings.wakePhrase]
            if engine == nil { await startEngine(services) }
        }
    }

    private func startEngine(_ services: AppServices) async {
        let engine = TranscriptionEngineFactory.make(microphone: services.microphone)
        self.engine = engine
        do {
            try await engine.start { [weak self] update in self?.handle(update) }
            AssistantTrace.trace.logIfChanged("wake", "wake phrase listening")
            state = .waiting
        } catch {
            self.engine = nil
            AssistantTrace.trace.logIfChanged("wake", "wake phrase failed to start: \(error.localizedDescription)")
            state = .off(error.localizedDescription)
        }
    }

    private func stopEngine() async {
        await engine?.stop()
        engine = nil
        detector = nil
    }

    private func handle(_ update: TranscriptUpdate) {
        switch state {
        case .waiting:
            if let rest = WakePhraseMatcher.remainder(after: phrase, in: update.text) {
                AssistantTrace.trace.log("wake phrase heard in \"\(update.text)\"")
                state = .capturing
                command = rest
                var detector = EndOfSpeechDetector(silence: (services?.settings[AssistantSettings.listeningPatience] ?? .normal).silence)
                detector.noSpeechTimeout = 5
                detector.note(rest, isFinal: false)
                self.detector = detector
                onWake?()
                onPartial?(rest)
            } else if update.isFinal {
                engine?.reset()
            }
        case .capturing:
            command = WakePhraseMatcher.remainder(after: phrase, in: update.text) ?? command
            AssistantTrace.trace.logIfChanged("capture", "heard \"\(update.text)\" final \(update.isFinal) -> request \"\(command)\"")
            detector?.note(command, isFinal: update.isFinal)
            onPartial?(command)
        case .off:
            break
        }
    }

    private func finishCaptureIfDone() {
        guard let detector, detector.shouldEnd() != nil else { return }
        self.detector = nil
        let finished = command
        AssistantTrace.trace.log("request ended: \"\(finished)\"")
        command = ""
        Task {
            await stopEngine()
            state = .off("Handing over")
            onCommand?(finished)
        }
    }
}
