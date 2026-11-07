import Foundation
import HomePadCore

/// Distance and proximity math shared by every sensing path.
enum ProximityMath {
    /// Typical adult face width covered by a Vision face bounding box, in meters.
    /// Needs on-device calibration (see README).
    static let averageFaceWidthMeters = 0.16
    /// Typical width of the upper-body box Vision draws around a person, in
    /// meters. Rough (build, posture, framing), so fusion calibrates it on faces.
    static let averageUpperBodyWidthMeters = 0.5

    /// Focal length in pixels for an image `imageWidth` pixels wide along the
    /// axis the field of view was measured on.
    static func focalLengthPixels(imageWidth: Double, horizontalFOVDegrees: Double) -> Double? {
        guard imageWidth > 0, horizontalFOVDegrees > 0, horizontalFOVDegrees < 180 else { return nil }
        let halfAngle = horizontalFOVDegrees * .pi / 360
        return (imageWidth / 2) / tan(halfAngle)
    }

    /// Pinhole estimate of the distance to a face that spans `faceWidthPixels`.
    /// Pixels are square, so the same focal length works in any orientation.
    static func distanceMeters(
        faceWidthPixels: Double, focalLengthPixels: Double, faceWidthMeters: Double = averageFaceWidthMeters
    ) -> Double? {
        guard faceWidthPixels > 1, focalLengthPixels > 0 else { return nil }
        return faceWidthMeters * focalLengthPixels / faceWidthPixels
    }

    /// Maps a distance to a proximity level with hysteresis, so someone standing
    /// right at a threshold does not make the UI flicker between layouts.
    /// The level only changes once the distance is `margin` meters past the boundary.
    static func level(for distance: Double, current: ProximityLevel, margin: Double = 0.15) -> ProximityLevel {
        let candidate = ProximityLevel.from(distanceMeters: distance)
        guard current != .nobody, candidate != current else { return candidate }
        if candidate > current {
            // Moving closer: the level must hold even if the person were `margin` farther away.
            return ProximityLevel.from(distanceMeters: distance + margin) >= candidate
                ? candidate : max(current, ProximityLevel.from(distanceMeters: distance + margin))
        } else {
            // Moving away: the level must hold even if the person were `margin` closer.
            return ProximityLevel.from(distanceMeters: max(0, distance - margin)) <= candidate
                ? candidate : min(current, ProximityLevel.from(distanceMeters: max(0, distance - margin)))
        }
    }
}

/// Smooths noisy per-frame distances with an exponential moving average.
/// Large jumps (a different person stepping in) reset the average.
struct DistanceSmoother: Sendable {
    var alpha = 0.35
    var resetJumpMeters = 1.2
    private(set) var value: Double?

    mutating func add(_ sample: Double) -> Double {
        guard let current = value, abs(sample - current) < resetJumpMeters else {
            value = sample
            return sample
        }
        let next = current + alpha * (sample - current)
        value = next
        return next
    }

    mutating func reset() { value = nil }
}
