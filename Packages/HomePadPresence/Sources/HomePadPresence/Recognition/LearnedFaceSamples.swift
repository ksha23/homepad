import Foundation

/// Embeddings learned from use for one member, kept apart from the enrolled
/// template (`FaceTemplate`), which learning never changes.
///
/// Stored in their own file next to the templates (`FaceTemplateStore`).
/// Re-enrolling, deleting the member's face data or resetting them in
/// Settings removes them.
struct LearnedFaceSamples: Codable, Equatable, Sendable {
    var memberID: UUID
    /// Feature print revision, the same as the member's template.
    var featurePrintRevision: Int
    /// Oldest first.
    var samples: [LearnedFaceSample]

    var embeddings: [[Float]] { samples.map(\.embedding) }

    /// Adds a sample, dropping the oldest ones beyond `cap`.
    mutating func append(_ sample: LearnedFaceSample, cap: Int) {
        samples.append(sample)
        if samples.count > cap { samples.removeFirst(samples.count - cap) }
    }
}

/// One embedding learned while a recognized member stayed in view.
struct LearnedFaceSample: Codable, Equatable, Sendable {
    /// Unit-length embedding.
    var embedding: [Float]
    var learnedAt: Date
    /// Best similarity to the member's enrolled embeddings when it was learned.
    var enrolledScore: Double
    /// Depth relief of the face, in meters.
    var reliefMeters: Double
}
