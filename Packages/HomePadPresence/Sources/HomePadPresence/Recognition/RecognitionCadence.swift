import Foundation

/// How often recognition samples a face while nobody is confirmed yet.
///
/// The voter needs several matching samples (4 for Standard), so the time
/// between samples sets how long recognition takes. Sampling runs at the
/// strictness's fast rate at the start of each look and while a member's votes
/// are building, so Standard's four votes take about 0.6 s instead of 1.5 s.
/// A face that keeps not matching, such as a guest's, drops back to the slow
/// rate after `burstSeconds`, so an unknown visitor costs no more power than
/// before.
struct RecognitionCadence: Equatable, Sendable {
    /// Seconds between samples for a face that keeps not matching. This was the
    /// rate for every sample before the fast rate existed.
    static let slowInterval: TimeInterval = 0.5

    /// How long sampling stays fast at the start of a look without any match.
    var burstSeconds: TimeInterval = 3
    /// A pause in sampling this long (the face left the range or turned away)
    /// starts a new look with a new fast burst.
    var restartGap: TimeInterval = 2

    private var burstStart: Date?
    private var lastSampleAt: Date?
    private var lastWasMatch = false

    /// Records one sample. `decision` is nil for a sample that was skipped.
    mutating func record(_ decision: MatchDecision?, at time: Date) {
        if burstStart == nil || lastSampleAt.map({ time.timeIntervalSince($0) > restartGap }) ?? true {
            burstStart = time
        }
        lastSampleAt = time
        lastWasMatch = decision?.memberID != nil
    }

    /// Seconds the analyzer should leave between samples from `now` on.
    /// - Parameter fastInterval: the rate while a match is likely, from
    ///   `RecognitionStrictness.fastSampleInterval`.
    func interval(at now: Date, fastInterval: TimeInterval) -> TimeInterval {
        if lastWasMatch { return fastInterval }
        guard let burstStart, let lastSampleAt, now.timeIntervalSince(lastSampleAt) <= restartGap else {
            // No look in progress: the next sample starts a new burst.
            return fastInterval
        }
        return now.timeIntervalSince(burstStart) < burstSeconds ? fastInterval : Self.slowInterval
    }

    mutating func reset() {
        burstStart = nil
        lastSampleAt = nil
        lastWasMatch = false
    }
}
