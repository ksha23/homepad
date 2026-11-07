import Accelerate
import Foundation

/// A household member's enrolled face, as a set of embeddings from several angles.
struct FaceTemplate: Codable, Equatable, Sendable {
    var memberID: UUID
    /// Unit-length embeddings, one per captured angle.
    var embeddings: [[Float]]
    /// Vision feature print revision the embeddings came from. Templates from a
    /// different revision are not comparable and must be re-enrolled.
    var featurePrintRevision: Int
    var createdAt: Date
}

/// The matcher's verdict for one embedding.
enum MatchDecision: Equatable, Sendable {
    case member(UUID, score: Double)
    case unknown(bestScore: Double)
    /// The face failed the liveness check (a photo or a screen).
    case spoof

    var memberID: UUID? {
        if case .member(let id, _) = self { return id }
        return nil
    }

    var score: Double? {
        switch self {
        case .member(_, let score): score
        case .unknown(let best): best
        case .spoof: nil
        }
    }
}

/// Compares an embedding against enrolled templates with cosine similarity.
///
/// A match needs both an absolute threshold and a margin over the runner-up,
/// so two similar-looking members do not get confused.
struct FaceMatcher: Equatable, Sendable {
    /// Minimum cosine similarity to accept.
    var acceptThreshold: Double
    /// Minimum lead of the best member over the second best.
    var margin: Double

    func match(_ embedding: [Float], against templates: [FaceTemplate]) -> MatchDecision {
        var scored: [(UUID, Double)] = templates.compactMap { template in
            let best = template.embeddings.map { Self.cosine(embedding, $0) }.max()
            return best.map { (template.memberID, $0) }
        }
        scored.sort { $0.1 > $1.1 }
        guard let best = scored.first else { return .unknown(bestScore: 0) }
        let runnerUp = scored.dropFirst().first?.1 ?? -1
        if best.1 >= acceptThreshold && best.1 - runnerUp >= margin {
            return .member(best.0, score: best.1)
        }
        return .unknown(bestScore: best.1)
    }

    /// Cosine similarity of two vectors. Returns 0 for mismatched or empty input.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = vDSP.dot(a, b)
        let norms = vDSP.sumOfSquares(a).squareRoot() * vDSP.sumOfSquares(b).squareRoot()
        guard norms > 0 else { return 0 }
        return Double(dot / norms)
    }

    /// Scales a vector to unit length (no-op for a zero vector).
    static func normalized(_ v: [Float]) -> [Float] {
        let norm = vDSP.sumOfSquares(v).squareRoot()
        guard norm > 0 else { return v }
        return vDSP.divide(v, norm)
    }
}
