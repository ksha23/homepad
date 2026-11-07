import CoreGraphics
import Foundation
import HomePadCore

/// Hand joints the recognizer uses (a subset of Vision's hand pose joints).
enum HandJoint: CaseIterable, Sendable {
    case wrist
    case thumbMP, thumbTip
    case indexMCP, indexPIP, indexTip
    case middleMCP, middlePIP, middleTip
    case ringMCP, ringPIP, ringTip
    case littleMCP, littlePIP, littleTip
}

/// One hand in one frame. Points are normalized and seen from the user's side:
/// x grows toward the user's right, y grows upward.
struct HandPoseSample: Sendable {
    var time: TimeInterval
    var points: [HandJoint: CGPoint]
}

/// Recognizes a deliberately held open palm from hand poses.
///
/// The palm fires once it shows in most frames of the last `holdDuration`, once
/// per hold. It has to be deliberate: every visible finger straight, the hand
/// large in the image (raised toward the iPad, not resting across the room),
/// held still, and pointing up. Looser rules toggled the music on their own.
/// Missed frames do not restart the hold: Vision loses a joint every few frames,
/// more so in dim light.
///
/// Which way is up in the image is learned from open hands, since people raise a
/// hand fingers up. On the 3rd generation 11-inch iPad Pro the image reaches
/// Vision upside down, so a fixed "up" read every palm as pointing down.
struct HandGestureRecognizer: Sendable {
    var holdDuration: TimeInterval = 0.8
    /// Share of the frames in the hold that must show the palm.
    var holdShare = 0.75
    /// Smallest wrist-to-fingertip span, as a share of the image.
    var minimumSpan: CGFloat = 0.12
    /// How far the palm may drift during the hold, as a share of the image.
    var maximumDrift: CGFloat = 0.06
    var cooldown: TimeInterval = 1.0

    /// Recent frames: whether each showed the palm, and where the palm was.
    private var frames: [(time: TimeInterval, isPalm: Bool, center: CGPoint?)] = []
    /// The palm already fired during the current hold.
    private var firedThisHold = false
    /// Recent open hands' finger directions, which point up in the room.
    private var openHandAxes: [CGVector] = []
    private var lastFired: TimeInterval = -.infinity

    /// Up in the image, once a few open hands were seen.
    var imageUp: CGVector? {
        guard openHandAxes.count >= 5 else { return nil }
        let sum = openHandAxes.reduce(CGVector.zero) { CGVector(dx: $0.dx + $1.dx, dy: $0.dy + $1.dy) }
        let length = hypot(sum.dx, sum.dy)
        return length > 0.01 ? CGVector(dx: sum.dx / length, dy: sum.dy / length) : nil
    }

    /// Feeds one frame. Pass `nil` when no hand is visible.
    mutating func process(_ sample: HandPoseSample?, at time: TimeInterval) -> HandGesture? {
        let up = imageUp
        let isPalm = sample.map { isDeliberatePalm($0, up: up) } ?? false
        frames.append((time, isPalm, sample.flatMap(Self.palmCenter)))
        frames.removeAll { time - $0.time > holdDuration }
        if let sample, Self.isOpenHand(sample), let axis = Self.axis(sample) {
            openHandAxes.append(axis)
            if openHandAxes.count > 20 { openHandAxes.removeFirst() }
        }
        // Once the palm is gone from the window, it may fire again.
        if !frames.contains(where: \.isPalm) { firedThisHold = false }
        guard !firedThisHold, time - lastFired >= cooldown,
              let oldest = frames.first?.time, time - oldest >= holdDuration * 0.75, frames.count >= 3,
              Double(frames.filter(\.isPalm).count) >= Double(frames.count) * holdShare,
              isSteady() else { return nil }
        firedThisHold = true
        lastFired = time
        return .openPalm
    }

    /// The palm stayed in place during the hold, so a waving or moving hand never fires.
    private func isSteady() -> Bool {
        let centers = frames.filter(\.isPalm).compactMap(\.center)
        guard let first = centers.first else { return false }
        return centers.allSatisfy { Self.distance($0, first) <= maximumDrift }
    }

    private func isDeliberatePalm(_ sample: HandPoseSample, up: CGVector?) -> Bool {
        guard Self.staticPose(sample, up: up) == .openPalm,
              let wrist = sample.points[.wrist], let tip = sample.points[.middleTip] ?? sample.points[.indexTip] else { return false }
        return Self.distance(wrist, tip) >= minimumSpan
    }

    // MARK: Pose geometry

    static func palmCenter(_ sample: HandPoseSample) -> CGPoint? {
        guard let wrist = sample.points[.wrist], let middle = sample.points[.middleMCP] else { return nil }
        return CGPoint(x: (wrist.x + middle.x) / 2, y: (wrist.y + middle.y) / 2)
    }

    private static let fingers: [(HandJoint, HandJoint)] = [
        (.indexMCP, .indexTip), (.middleMCP, .middleTip), (.ringMCP, .ringTip), (.littleMCP, .littleTip),
    ]

    /// Unit vector from the wrist toward the middle knuckle.
    static func axis(_ sample: HandPoseSample) -> CGVector? {
        guard let wrist = sample.points[.wrist], let middle = sample.points[.middleMCP] else { return nil }
        let length = distance(wrist, middle)
        guard length > 0.01 else { return nil }
        return CGVector(dx: (middle.x - wrist.x) / length, dy: (middle.y - wrist.y) / length)
    }

    /// At least three fingers visible, and every visible one straight.
    static func isOpenHand(_ sample: HandPoseSample) -> Bool {
        let ratios = fingers.compactMap { extensionRatio(sample, base: $0.0, tip: $0.1) }
        return ratios.count >= 3 && ratios.allSatisfy { $0 > 1.55 }
    }

    /// An open palm, if the hand currently forms one. `up` is the image's up when
    /// known: the fingers must point within about 45 degrees of it.
    static func staticPose(_ sample: HandPoseSample, up: CGVector? = nil) -> HandGesture? {
        guard isOpenHand(sample) else { return nil }
        if let up, let axis = axis(sample), axis.dx * up.dx + axis.dy * up.dy < 0.7 { return nil }
        return .openPalm
    }

    /// The hand as the trace shows it: joints found, each finger's extension
    /// ratio, which way the fingers point in the image (0 is up, 90 is right),
    /// the learned up, and whether it counts as a deliberate palm.
    func describe(_ sample: HandPoseSample?) -> String {
        guard let sample else { return "no hand" }
        let degrees = { (vector: CGVector) in String(Int((atan2(vector.dx, vector.dy) * 180 / .pi).rounded())) }
        let ratios = Self.fingers.map { Self.extensionRatio(sample, base: $0.0, tip: $0.1).map { String(format: "%.1f", $0) } ?? "-" }
        let span = sample.points[.wrist].flatMap { wrist in sample.points[.middleTip].map { Self.distance(wrist, $0) } }
        return "hand \(sample.points.count) joints fingers \(ratios.joined(separator: "/")) pointing \(Self.axis(sample).map(degrees) ?? "-") "
            + "up \(imageUp.map(degrees) ?? "unknown") span \(span.map { String(format: "%.2f", $0) } ?? "-") "
            + "palm \(isDeliberatePalm(sample, up: imageUp))"
    }

    /// Wrist-to-tip distance over wrist-to-knuckle distance. About 2 when the
    /// finger is straight, close to 1 when it is curled into the palm.
    private static func extensionRatio(_ s: HandPoseSample, base: HandJoint, tip: HandJoint) -> CGFloat? {
        guard let wrist = s.points[.wrist], let mcp = s.points[base], let end = s.points[tip] else { return nil }
        let knuckle = distance(wrist, mcp)
        guard knuckle > 0.01 else { return nil }
        return distance(wrist, end) / knuckle
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
