import Foundation

/// Decides when a spoken request is over: a pause after the last new words,
/// nothing heard at all, or a hard time limit. Pure timing logic.
struct EndOfSpeechDetector: Equatable {
    enum Reason: Equatable {
        case pause
        case nothingHeard
        case timeLimit
    }

    /// Seconds of silence after the last change in the transcript.
    var silence: TimeInterval
    /// Give up when nothing was recognized for this long.
    var noSpeechTimeout: TimeInterval = 6
    /// Never listen longer than this.
    var maxDuration: TimeInterval = 30

    private let start: Date
    private var lastChange: Date?
    private var lastText = ""
    private var finalAt: Date?

    init(silence: TimeInterval, start: Date = Date()) {
        self.silence = silence
        self.start = start
    }

    var heardSomething: Bool { !lastText.isEmpty }

    mutating func note(_ text: String, isFinal: Bool, at now: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != lastText {
            lastText = trimmed
            lastChange = now
            finalAt = nil
        }
        if isFinal, !trimmed.isEmpty { finalAt = now }
    }

    /// A final result from the recognizer shortens the wait to half the pause.
    func shouldEnd(at now: Date = Date()) -> Reason? {
        if now.timeIntervalSince(start) >= maxDuration { return .timeLimit }
        guard let lastChange, heardSomething else {
            return now.timeIntervalSince(start) >= noSpeechTimeout ? .nothingHeard : nil
        }
        if let finalAt, now.timeIntervalSince(finalAt) >= silence / 2 { return .pause }
        return now.timeIntervalSince(lastChange) >= silence ? .pause : nil
    }
}
