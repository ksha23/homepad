import Foundation
import HomePadCore

/// One head attitude reading from AirPods, in radians.
struct HeadMotionSample: Equatable, Sendable {
    var time: TimeInterval
    /// Nodding axis (chin up and down).
    var pitch: Double
    /// Shaking axis (turning left and right).
    var yaw: Double
}

/// Detects a nod (yes) or a head shake (no) from a stream of head attitudes.
///
/// It counts "legs": movements along one axis of at least `legThreshold`
/// that reverse direction. A nod is two pitch legs (down and back up) inside
/// the window, a shake is three yaw legs (one side, the other side, back).
/// The other axis must stay comparatively still, so looking around the room
/// or a diagonal head roll does not count. After a detection the window is
/// cleared and a cooldown prevents double triggers.
struct HeadGestureDetector: Sendable {
    var window: TimeInterval = 1.5
    var nodLegThreshold = 9.0 * .pi / 180
    var shakeLegThreshold = 12.0 * .pi / 180
    var nodLegs = 2
    var shakeLegs = 3
    /// The quiet axis may move at most this fraction of the gesture axis.
    var crossAxisRatio = 0.6
    var cooldown: TimeInterval = 1.0

    private var samples: [HeadMotionSample] = []
    private var lastDetection: TimeInterval = -.infinity

    mutating func add(_ sample: HeadMotionSample) -> HeadGesture? {
        samples.append(sample)
        samples.removeAll { sample.time - $0.time > window }
        guard sample.time - lastDetection >= cooldown, samples.count >= 4 else { return nil }

        let pitches = samples.map(\.pitch)
        let yaws = samples.map(\.yaw)
        let pitchRange = Self.range(pitches)
        let yawRange = Self.range(yaws)

        var detected: HeadGesture?
        if Self.legs(in: yaws, threshold: shakeLegThreshold) >= shakeLegs, pitchRange <= yawRange * crossAxisRatio {
            detected = .shake
        } else if Self.legs(in: pitches, threshold: nodLegThreshold) >= nodLegs, yawRange <= pitchRange * crossAxisRatio {
            detected = .nod
        }
        if detected != nil {
            lastDetection = sample.time
            samples.removeAll()
        }
        return detected
    }

    mutating func reset() {
        samples.removeAll()
        lastDetection = -.infinity
    }

    /// Counts direction reversals separated by at least `threshold` (a zigzag filter).
    static func legs(in values: [Double], threshold: Double) -> Int {
        guard let first = values.first else { return 0 }
        var legs = 0
        var direction = 0
        var extreme = first
        for value in values.dropFirst() {
            switch direction {
            case 0:
                if abs(value - extreme) >= threshold {
                    direction = value > extreme ? 1 : -1
                    legs = 1
                    extreme = value
                }
            case 1:
                if value > extreme {
                    extreme = value
                } else if extreme - value >= threshold {
                    direction = -1
                    legs += 1
                    extreme = value
                }
            default:
                if value < extreme {
                    extreme = value
                } else if value - extreme >= threshold {
                    direction = 1
                    legs += 1
                    extreme = value
                }
            }
        }
        return legs
    }

    private static func range(_ values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }
}
