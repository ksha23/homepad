import Foundation

/// When the steps of one recognition happened, for the presence trace
/// (`-HomePadPresenceTrace`): the first face of a look, the first sample, and
/// how many samples and seconds it took to recognize someone.
struct RecognitionTimeline: Equatable, Sendable {
    /// A face seen again after this many seconds without one, and before any
    /// sample, starts a new look (a sighting that never became presence).
    var lookGap: TimeInterval = 5

    private(set) var firstFaceAt: Date?
    private(set) var firstSampleAt: Date?
    private(set) var samples = 0
    private(set) var skipped = 0
    private var lastFaceAt: Date?

    /// Notes a frame with a face. Returns true when it is the first face of a look.
    mutating func noteFace(at time: Date) -> Bool {
        defer { lastFaceAt = time }
        let stale = lastFaceAt.map { time.timeIntervalSince($0) > lookGap } ?? true
        guard firstFaceAt == nil || (firstSampleAt == nil && stale) else { return false }
        firstFaceAt = time
        return true
    }

    /// Notes a sample. Returns true when it is the first sample of the look.
    mutating func noteSample(skipped wasSkipped: Bool, at time: Date) -> Bool {
        samples += 1
        if wasSkipped { skipped += 1 }
        guard firstSampleAt == nil else { return false }
        firstSampleAt = time
        return true
    }

    /// Seconds from the first face to `time`, if a face was seen.
    func sinceFirstFace(_ time: Date) -> TimeInterval? {
        firstFaceAt.map { time.timeIntervalSince($0) }
    }

    /// "after 4 samples (1 skipped) in 0.62 s, 3.10 s after the first face".
    func summary(at time: Date) -> String {
        let sampling = firstSampleAt.map { Self.seconds(time.timeIntervalSince($0)) } ?? "?"
        var text = "after \(samples) samples (\(skipped) skipped) in \(sampling) s"
        if let face = sinceFirstFace(time) { text += ", \(Self.seconds(face)) s after the first face" }
        return text
    }

    static func seconds(_ value: TimeInterval) -> String { String(format: "%.2f", value) }

    mutating func reset() {
        self = RecognitionTimeline(lookGap: lookGap)
    }
}
