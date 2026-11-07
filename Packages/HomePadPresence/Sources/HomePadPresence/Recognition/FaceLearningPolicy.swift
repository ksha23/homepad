import Foundation

/// When a sample of a recognized member is worth keeping, so the next visit in
/// that pose, distance or light matches quickly, the way Face ID adapts to its
/// owner. Which track a sample may come from is `FaceLearningSession`'s job.
///
/// The numbers come from the presence traces of a HomePad in daily use (see the README,
/// "Learning from use").
struct FaceLearningPolicy: Equatable, Sendable {
    /// Lowest best similarity to the member's enrolled embeddings. Learned
    /// embeddings never count toward it, so learning cannot drift away from the
    /// enrolled face one small step at a time.
    var enrolledFloor = 0.70
    /// A sample at least this similar to any stored embedding of the member,
    /// enrolled or learned, adds nothing new.
    var noveltyCeiling = 0.90
    /// Depth relief a learned sample must show, in meters. The low end is the
    /// liveness cutoff. Above the high end the depth patch held more than a face
    /// (the background or a hand), and the crop likely did too.
    var reliefRange: ClosedRange<Double> = DepthLiveness.minimumReliefMeters...0.040
    /// Share of the face that must have depth.
    var minimumValidFraction = 0.9
    /// Learned samples kept per member. The oldest roll out.
    var capPerMember = 20
    /// Samples learned on one face track at most, so one long visit cannot
    /// replace everything learned on earlier ones.
    var perTrackLimit = 5
    /// Seconds between two learned samples at least.
    var minimumSpacing: TimeInterval = 6
    /// Seconds between samples taken only for learning.
    var sampleInterval: TimeInterval = 2
    /// How long one track samples for learning, which bounds the cost of
    /// someone sitting in view for hours.
    var trackWindow: TimeInterval = 300

    enum Verdict: Equatable, Sendable {
        /// Keep it. `enrolledScore` is its best similarity to the enrolled embeddings.
        case learn(enrolledScore: Double)
        case skip(SkipReason)
    }

    enum SkipReason: Equatable, Sendable {
        case notOneFace
        case noOwnDepth
        case flat
        case reliefOutOfRange(Double)
        case partialDepth(Double)
        case belowFloor(Double)
        case notNew(Double)
        case nearOtherMember(own: Double, other: Double)

        /// For the presence trace.
        var description: String {
            switch self {
            case .notOneFace: "not exactly one face in view"
            case .noOwnDepth: "no depth of its own"
            case .flat: "flat"
            case .reliefOutOfRange(let meters): "relief \(Self.format(meters * 1000))mm is not face shaped"
            case .partialDepth(let fraction): "depth on only \(Self.format(fraction)) of the face"
            case .belowFloor(let score): "score \(Self.format(score)) is below the floor"
            case .notNew(let score): "nothing new, \(Self.format(score)) to a stored sample"
            case .nearOtherMember(let own, let other):
                "too close to another member, \(Self.format(own)) against \(Self.format(other))"
            }
        }

        private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
    }

    /// Judges one sample of the member being learned.
    /// - Parameters:
    ///   - enrolled: the member's enrolled embeddings, for the floor.
    ///   - stored: the member's enrolled and learned embeddings, for novelty.
    ///   - others: every other member's enrolled and learned embeddings.
    ///   - margin: the matcher's margin over the runner-up.
    func evaluate(
        _ sample: FaceEmbeddingSample, enrolled: [[Float]], stored: [[Float]], others: [[[Float]]], margin: Double
    ) -> Verdict {
        guard sample.visibleFaces == 1 else { return .skip(.notOneFace) }
        // Only the sample's own depth check counts, never one carried over from
        // an earlier sample.
        guard let liveness = sample.liveness else { return .skip(.noOwnDepth) }
        guard liveness.isLive else { return .skip(.flat) }
        guard reliefRange.contains(liveness.reliefMeters) else { return .skip(.reliefOutOfRange(liveness.reliefMeters)) }
        guard liveness.validFraction >= minimumValidFraction else { return .skip(.partialDepth(liveness.validFraction)) }
        let enrolledScore = Self.best(sample.embedding, in: enrolled)
        guard enrolledScore >= enrolledFloor else { return .skip(.belowFloor(enrolledScore)) }
        let storedScore = Self.best(sample.embedding, in: stored)
        guard storedScore < noveltyCeiling else { return .skip(.notNew(storedScore)) }
        let otherScore = others.map { Self.best(sample.embedding, in: $0) }.max() ?? -1
        guard storedScore - otherScore >= margin else { return .skip(.nearOtherMember(own: storedScore, other: otherScore)) }
        return .learn(enrolledScore: enrolledScore)
    }

    static func best(_ embedding: [Float], in set: [[Float]]) -> Double {
        set.map { FaceMatcher.cosine(embedding, $0) }.max() ?? -1
    }
}
