import CoreGraphics
import Foundation

/// The slow pan and zoom on each photo.
struct KenBurnsMotion: Equatable {
    var startScale: CGFloat
    var endScale: CGFloat
    /// The point the zoom moves toward (or away from), normalized.
    var anchor: CGPoint

    /// A gentle motion for a photo. Zooms toward the subject when there is one,
    /// alternating zoom in and zoom out from photo to photo.
    static func make(seed: Int, subject: CGRect?) -> KenBurnsMotion {
        let zoomIn = seed % 2 == 0
        let anchor: CGPoint
        if let subject {
            anchor = CGPoint(x: clamp(subject.midX, 0.2, 0.8), y: clamp(subject.midY, 0.2, 0.8))
        } else {
            let corners = [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.35), CGPoint(x: 0.35, y: 0.7), CGPoint(x: 0.65, y: 0.65)]
            anchor = corners[abs(seed) % corners.count]
        }
        return KenBurnsMotion(startScale: zoomIn ? 1.0 : 1.12, endScale: zoomIn ? 1.12 : 1.0, anchor: anchor)
    }

    /// No move at all, for a face that shows one photo as it is.
    static let still = KenBurnsMotion(startScale: 1, endScale: 1, anchor: CGPoint(x: 0.5, y: 0.5))

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}
