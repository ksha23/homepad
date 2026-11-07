import Foundation

/// Listens for one spoken request and returns it once the person pauses.
/// Push-to-talk, follow-ups and yes or no answers all use this.
@MainActor
final class UtteranceListener {
    private let engine: any TranscriptionEngine
    private var detector: EndOfSpeechDetector
    private var latest = ""
    private var endedEarly = false

    init(engine: any TranscriptionEngine, silence: TimeInterval, noSpeechTimeout: TimeInterval = 6) {
        self.engine = engine
        self.detector = EndOfSpeechDetector(silence: silence)
        self.detector.noSpeechTimeout = noSpeechTimeout
    }

    /// Returns what was said (possibly empty). Cancel the calling task to abort.
    func listen(onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        try await engine.start { [weak self] update in
            guard let self else { return }
            self.latest = update.text
            self.detector.note(update.text, isFinal: update.isFinal)
            onPartial(update.text)
        }
        defer { Task { await engine.stop() } }
        while !endedEarly, detector.shouldEnd() == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        await engine.stop()
        return latest
    }

    /// Ends listening now and keeps what was heard (the person tapped the mic again).
    func finish() {
        endedEarly = true
    }
}
