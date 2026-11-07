import Foundation
import HomePadCore

extension AssistantRuntime {
    /// Push-to-talk, swipe-down and follow-ups: listen for one request, then answer it.
    func beginListening(followUp: Bool) {
        let isPresented = session.isPresented
        reset()
        var session = AssistantSession()
        session.isPresented = true
        session.isVoice = true
        // A follow-up keeps the previous answer visible until new words arrive.
        if followUp, isPresented { session.answer = self.session.answer }
        self.session = session
        phase = .listening

        listenTask = Task { [weak self] in
            guard let self else { return }
            do {
                let heard = try await self.listenForRequest(followUp: followUp)
                AssistantTrace.trace.log("\(followUp ? "follow-up" : "listening") heard \"\(heard)\"")
                if heard.isEmpty {
                    self.endVoiceExchange()
                    self.phase = .idle
                    // After a follow-up, the answer stays a moment longer to read.
                    self.scheduleAutoDismiss(after: .seconds(followUp ? 5 : 3))
                } else {
                    self.submitVoice(heard)
                }
            } catch is CancellationError {
                return
            } catch {
                AssistantTrace.trace.log("\(followUp ? "follow-up" : "listening") failed: \(error.localizedDescription)")
                // Nobody asked for a follow-up, so one that cannot start ends quietly.
                if followUp {
                    self.endVoiceExchange()
                    self.phase = .idle
                    self.scheduleAutoDismiss(after: .seconds(5))
                    return
                }
                self.session.errorMessage = error.localizedDescription
                self.phase = .error
                self.endVoiceExchange()
                self.scheduleAutoDismiss()
            }
        }
    }

    /// One request. A follow-up that fails to start (the transcriber still closing
    /// from the last request) tries once more, since it starts right after an answer.
    private func listenForRequest(followUp: Bool) async throws -> String {
        guard followUp else { return try await listenOnce(noSpeechTimeout: 7) }
        do {
            return try await listenOnce(noSpeechTimeout: 4)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AssistantTrace.trace.log("follow-up failed to start, trying again: \(error.localizedDescription)")
            try await Task.sleep(for: .milliseconds(500))
            return try await listenOnce(noSpeechTimeout: 4)
        }
    }

    /// Listens for one utterance with the person's chosen patience. Asks for permission on first use.
    ///
    /// The `.voice` claim takes the iPad's microphone for this one request, even
    /// from AirPlay multi-room playback, and ends with the listening.
    func listenOnce(noSpeechTimeout: TimeInterval) async throws -> String {
        guard services.settings[CoreSettings.microphoneEnabled] else { throw AssistantError.microphoneDisabled }
        guard await SpeechPermissions.request() else { throw AssistantError.permissionDenied("the microphone and speech recognition") }
        await wake.suspend()
        beginVoiceExchange()
        services.audioSession.claim(.voice, owner: Self.voiceOwner)
        defer {
            services.audioSession.release(owner: Self.voiceOwner)
            // Back in AirPlay multi-room there is no microphone: stop anyone still capturing.
            if !services.audioSession.isRecordingAvailable { services.microphone.suspend() }
        }
        guard services.audioSession.isRecordingAvailable else {
            throw AssistantError.speechUnavailable(services.audioSession.lastError ?? "The microphone is not available. Type your request instead.")
        }
        let engine = TranscriptionEngineFactory.make(microphone: services.microphone)
        let listener = UtteranceListener(
            engine: engine, silence: services.settings[AssistantSettings.listeningPatience].silence, noSpeechTimeout: noSpeechTimeout
        )
        self.listener = listener
        defer { self.listener = nil }
        return try await listener.listen { [weak self] text in self?.updateTranscript(text) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The audio session owner for a spoken request.
    static let voiceOwner = "assistant.voice"

    /// A spoken exchange starts: music on this iPad lowers until it ends.
    func beginVoiceExchange() {
        guard !holdsMediaForVoice else { return }
        holdsMediaForVoice = true
        services.media.duckForVoice()
    }

    /// A spoken exchange ended (answered, nothing heard, failed or cancelled):
    /// music lowered for it comes back up.
    func endVoiceExchange() {
        guard holdsMediaForVoice else { return }
        holdsMediaForVoice = false
        Task { await services.media.restoreAfterVoice() }
    }

    /// Says a message from elsewhere, such as a Home Assistant automation, in the
    /// assistant's voice, with music lowered as for an answer. Skipped while
    /// someone is talking to the assistant, so it never talks over a request or
    /// is heard as one. The sender shows the text too.
    func announce(_ text: String) {
        guard phase == .idle, listener == nil, !speech.isSpeaking else {
            AssistantTrace.trace.log("announcement skipped, the assistant is busy")
            return
        }
        AssistantTrace.trace.log("announcing \"\(text)\"")
        beginVoiceExchange()
        speech.enqueue(text)
        Task { [weak self] in
            await self?.speech.waitUntilDone()
            // A request that started meanwhile keeps the music lowered for itself.
            guard let self, self.phase == .idle else { return }
            self.endVoiceExchange()
        }
    }

    /// The wake phrase was heard: show the listening overlay right away.
    func wakeDetected() {
        reset()
        beginVoiceExchange()
        var session = AssistantSession()
        session.isPresented = true
        session.isVoice = true
        self.session = session
        phase = .listening
    }

    /// A finished spoken request from the wake phrase or push-to-talk.
    func submitVoice(_ text: String) {
        AssistantTrace.trace.log(text.isEmpty ? "empty spoken request, closing" : "spoken request \"\(text)\"")
        guard !text.isEmpty else {
            endVoiceExchange()
            phase = .idle
            session.isPresented = false
            return
        }
        submit(AssistantRequest(text: text), isVoice: true)
    }

    /// Speaks a confirmation question during voice sessions, then listens for yes or no.
    /// Taps and AirPods nods still work while it listens.
    func askAloud(_ prompt: ConfirmationCenter.Prompt) {
        session.isPresented = true
        guard session.isVoice else { return }
        Task { [weak self] in
            guard let self else { return }
            self.speech.enqueue(prompt.question)
            await self.speech.waitUntilDone()
            guard self.confirmations.pending?.id == prompt.id else { return }
            let previous = self.phase
            self.phase = .listening
            let heard = (try? await self.listenOnce(noSpeechTimeout: 6)) ?? ""
            if self.phase == .listening { self.phase = previous }
            if self.confirmations.pending?.id == prompt.id, !self.confirmations.resolve(spoken: heard), !heard.isEmpty {
                self.speech.enqueue("Please say yes or no, or tap a button.")
            }
        }
    }
}
