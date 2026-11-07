import AVFoundation
import HomePadCore
import Observation
import Speech

/// Listens for one spoken question on the shared microphone (`services.microphone`)
/// and transcribes it on device. Stops after a short pause.
@MainActor
@Observable
final class SpokenQuestionListener {
    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var problem: String?

    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var microphoneToken: UUID?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?
    @ObservationIgnored private weak var services: AppServices?

    /// Seconds of no new words before the question is considered finished.
    static let pause: Duration = .milliseconds(1600)

    /// Asks for permission the first time, then listens until a pause.
    func start(services: AppServices, onFinish: @escaping (String) -> Void) async {
        guard !isListening else { return }
        problem = nil
        transcript = ""
        guard await Self.requestPermissions() else {
            problem = "Allow Speech Recognition and the microphone for HomePad in Settings to ask out loud."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = "Speech recognition is not available right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .search
        self.request = request
        self.services = services
        self.onFinish = onFinish
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if let text { self.heard(text) }
                if isFinal || error != nil { self.finish() }
            }
        }
        microphoneToken = services.microphone.subscribe { buffer, _ in request.append(buffer) }
        if let micProblem = services.microphone.lastError, !services.microphone.isRunning {
            problem = micProblem
            cancel()
        }
    }

    /// Stops listening and delivers what was heard so far.
    func finish() {
        guard isListening else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinish
        teardown()
        if !text.isEmpty { callback?(text) }
    }

    /// Stops without delivering anything.
    func cancel() {
        guard isListening else { return }
        recognitionTask?.cancel()
        teardown()
    }

    private func heard(_ text: String) {
        transcript = text
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func teardown() {
        isListening = false
        silenceTask?.cancel()
        silenceTask = nil
        if let microphoneToken { services?.microphone.unsubscribe(microphoneToken) }
        microphoneToken = nil
        request?.endAudio()
        request = nil
        recognitionTask = nil
        onFinish = nil
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
