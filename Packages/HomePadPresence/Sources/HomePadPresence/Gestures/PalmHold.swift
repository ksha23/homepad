import CoreGraphics
import Foundation

/// A palm held up and still: it fires once it shows in most frames of the
/// last `holdDuration`, once per hold, so a hand passing by or waving never
/// fires. Missed frames do not restart the hold: the detectors lose the
/// hand every few frames.
///
/// Fed by `DepthPalmDetector` on iPads with TrueDepth, one depth map at a
/// time, and by `HandGestureRecognizer` (camera hand pose) on the others.
/// Centers are normalized in the frame or depth map they came from.
struct PalmHold: Sendable {
    var holdDuration: TimeInterval = 0.8
    /// Share of the frames in the hold that must show the palm.
    var holdShare = 0.75
    /// How far the palm may drift during the hold, as a share of the frame.
    var maximumDrift: CGFloat = 0.06
    var cooldown: TimeInterval = 1.0

    /// Recent frames: whether each showed the palm, and where it was.
    private var frames: [(time: TimeInterval, isPalm: Bool, center: CGPoint?)] = []
    /// The palm already fired during the current hold.
    private var firedThisHold = false
    private var lastFired: TimeInterval = -.infinity

    /// Notes one frame. Returns true when the palm fires.
    mutating func note(isPalm: Bool, center: CGPoint?, at time: TimeInterval) -> Bool {
        frames.append((time, isPalm, center))
        frames.removeAll { time - $0.time > holdDuration }
        // Once the palm is gone from the window, it may fire again.
        if !frames.contains(where: \.isPalm) { firedThisHold = false }
        guard !firedThisHold, time - lastFired >= cooldown,
              let oldest = frames.first?.time, time - oldest >= holdDuration * 0.75, frames.count >= 3,
              Double(frames.filter(\.isPalm).count) >= Double(frames.count) * holdShare,
              isSteady() else { return false }
        firedThisHold = true
        lastFired = time
        return true
    }

    /// The palm stayed in place during the hold.
    private func isSteady() -> Bool {
        let centers = frames.filter(\.isPalm).compactMap(\.center)
        guard let first = centers.first else { return false }
        return centers.allSatisfy { hypot($0.x - first.x, $0.y - first.y) <= maximumDrift }
    }
}
