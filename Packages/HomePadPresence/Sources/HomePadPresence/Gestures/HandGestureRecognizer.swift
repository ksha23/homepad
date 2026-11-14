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

/// Recognizes a deliberately held open palm from camera hand poses, on iPads
/// without TrueDepth. With TrueDepth the palm comes from depth instead
/// (`DepthPalmDetector`): camera hand pose was unreliable.
///
/// The palm has to be deliberate: every visible finger straight, the hand
/// large in the image (raised toward the iPad, not resting across the room),
/// pointing up, and held still (`PalmHold`). Looser rules toggled the music
/// on their own.
///
/// Which way is up in the image is learned from open hands, since people raise a
/// hand fingers up. On the 3rd generation 11-inch iPad Pro the image reaches
/// Vision upside down, so a fixed "up" read every palm as pointing down.
struct HandGestureRecognizer: Sendable {
    /// Smallest wrist-to-fingertip span, as a share of the image.
    var minimumSpan: CGFloat = 0.12
    private var hold = PalmHold()
    /// Recent open hands' finger directions, which point up in the room.
    private var openHandAxes: [CGVector] = []

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
        if let sample, Self.isOpenHand(sample), let axis = Self.axis(sample) {
            openHandAxes.append(axis)
            if openHandAxes.count > 20 { openHandAxes.removeFirst() }
        }
        return hold.note(isPalm: isPalm, center: sample.flatMap(Self.palmCenter), at: time) ? .openPalm : nil
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
