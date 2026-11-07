import AVFoundation
import Foundation
import HomePadCore
import Speech

/// Fallback speech to text with SFSpeechRecognizer, forced on device so audio
/// never leaves the iPad. Used where SpeechTranscriber is unavailable.
@MainActor
final class LegacyTranscriptionEngine: TranscriptionEngine {
    private let microphone: MicrophoneHub
    private let recognizer: SFSpeechRecognizer?
    private let sink = RequestSink()
    private var task: SFSpeechRecognitionTask?
    private var subscription: UUID?
    private var onUpdate: (@MainActor (TranscriptUpdate) -> Void)?
    /// Text from earlier recognition tasks since the last reset. SFSpeechRecognizer
    /// ends a task after each final result, so it is restarted and the text carried over.
    private var carried = ""

    init(microphone: MicrophoneHub, locale: Locale) {
        self.microphone = microphone
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    func start(onUpdate: @escaping @MainActor (TranscriptUpdate) -> Void) async throws {
        await stop()
        guard let recognizer, recognizer.isAvailable else {
            throw AssistantError.speechUnavailable("Speech recognition is not available right now.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AssistantError.speechUnavailable("This iPad cannot recognize speech on device for this language.")
        }
        self.onUpdate = onUpdate
        beginTask()
        let sink = self.sink
        subscription = microphone.subscribe { buffer, _ in sink.append(buffer) }
    }

    func stop() async {
        if let subscription { microphone.unsubscribe(subscription) }
        subscription = nil
        onUpdate = nil
        carried = ""
        task?.cancel()
        task = nil
        sink.replace(with: nil)
    }

    func reset() {
        carried = ""
        restart()
    }

    /// Starts a fresh recognition task, keeping the carried text (also avoids the one minute limit).
    private func restart() {
        guard onUpdate != nil else { return }
        task?.cancel()
        beginTask()
    }

    private func beginTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        sink.replace(with: request)
        task = Self.recognize(request, with: recognizer) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                guard let self, self.sink.isCurrent(request) else { return }
                let combined = text.map { [self.carried, $0].filter { !$0.isEmpty }.joined(separator: " ") }
                if isFinal, let combined { self.carried = combined }
                // Recognition stops after a final result or an error. Keep listening while started.
                if isFinal || failed { self.restart() }
                if let combined { self.onUpdate?(TranscriptUpdate(text: combined, isFinal: isFinal)) }
            }
        }
    }

    /// Starts recognition from a nonisolated context, so the recognizer's background
    /// callback is not treated as main-actor code.
    nonisolated private static func recognize(
        _ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer,
        handler: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// Hands audio-thread buffers to whichever request is current.
    private final class RequestSink: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?

        func replace(with newRequest: SFSpeechAudioBufferRecognitionRequest?) {
            lock.withLock {
                request?.endAudio()
                request = newRequest
            }
        }

        func isCurrent(_ candidate: SFSpeechAudioBufferRecognitionRequest) -> Bool {
            lock.withLock { request === candidate }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.withLock { request?.append(buffer) }
        }
    }
}
