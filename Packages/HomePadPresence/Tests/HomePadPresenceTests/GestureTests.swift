import CoreGraphics
import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

@Suite struct HeadGestureTests {
    private let degree = Double.pi / 180

    /// A 25 Hz trace from AirPods with a little sensor noise.
    private func trace(seconds: Double, pitch: (Double) -> Double, yaw: (Double) -> Double) -> [HeadMotionSample] {
        var generator = SplitMix64(state: 42)
        return stride(from: 0.0, through: seconds, by: 0.04).map { t in
            let noise = { (Double(generator.nextFloat()) - 0.5) * 0.6 * self.degree }
            return HeadMotionSample(time: t, pitch: pitch(t) + noise(), yaw: yaw(t) + noise())
        }
    }

    private func run(_ samples: [HeadMotionSample]) -> [HeadGesture] {
        var detector = HeadGestureDetector()
        return samples.compactMap { detector.add($0) }
    }

    @Test func nodIsYes() {
        // Chin down 15 degrees and back up, twice, in about a second.
        let nod = trace(seconds: 1.0, pitch: { -15 * self.degree * sin(2 * .pi * 2 * $0).magnitude }, yaw: { _ in 0 })
        #expect(run(nod) == [.nod])
    }

    @Test func shakeIsNo() {
        let shake = trace(seconds: 1.4, pitch: { _ in 0 }, yaw: { 20 * self.degree * sin(2 * .pi * 1.6 * $0) })
        #expect(run(shake) == [.shake])
    }

    @Test func slowLookAroundIsNothing() {
        // Turning 40 degrees over four seconds, then back, is looking around.
        let look = trace(seconds: 8, pitch: { _ in 0 }, yaw: { 40 * self.degree * sin(2 * .pi * $0 / 8) })
        #expect(run(look).isEmpty)
    }

    @Test func diagonalMovementIsNothing() {
        // Pitch and yaw moving together is neither a clean nod nor a shake.
        let wobble = trace(seconds: 1.4, pitch: { 15 * self.degree * sin(2 * .pi * 1.6 * $0) },
                           yaw: { 15 * self.degree * sin(2 * .pi * 1.6 * $0) })
        #expect(run(wobble).isEmpty)
    }

    @Test func stillHeadIsNothing() {
        #expect(run(trace(seconds: 3, pitch: { _ in 0 }, yaw: { _ in 0 })).isEmpty)
    }

    @Test func cooldownPreventsDoubleTrigger() {
        // A long vigorous nod still counts once per cooldown.
        let nod = trace(seconds: 0.9, pitch: { -15 * self.degree * sin(2 * .pi * 3 * $0).magnitude }, yaw: { _ in 0 })
        #expect(run(nod).count == 1)
    }

    @Test func legCounting() {
        #expect(HeadGestureDetector.legs(in: [0, -10, 0], threshold: 5) == 2)
        #expect(HeadGestureDetector.legs(in: [0, 10, -10, 10], threshold: 5) == 3)
        #expect(HeadGestureDetector.legs(in: [0, 3, -3, 3], threshold: 5) == 0)
        #expect(HeadGestureDetector.legs(in: [], threshold: 5) == 0)
    }
}

@Suite struct HandGestureTests {
    /// A hand in user-perspective coordinates, centered at (x, y).
    private func hand(at x: CGFloat, y: CGFloat = 0.5, fingersOpen: Bool, time: TimeInterval) -> HandPoseSample {
        var points: [HandJoint: CGPoint] = [.wrist: CGPoint(x: x, y: y - 0.1)]
        let reach: CGFloat = fingersOpen ? 0.2 : 0.06
        let fingers: [(HandJoint, HandJoint, HandJoint, CGFloat)] = [
            (.indexMCP, .indexPIP, .indexTip, -0.03), (.middleMCP, .middlePIP, .middleTip, -0.01),
            (.ringMCP, .ringPIP, .ringTip, 0.01), (.littleMCP, .littlePIP, .littleTip, 0.03),
        ]
        for (mcp, pip, tip, dx) in fingers {
            points[mcp] = CGPoint(x: x + dx, y: y)
            points[pip] = CGPoint(x: x + dx, y: y + reach * 0.5)
            points[tip] = CGPoint(x: x + dx, y: fingersOpen ? y + reach : y - 0.04)
        }
        points[.thumbMP] = CGPoint(x: x - 0.05, y: y - 0.02)
        points[.thumbTip] = CGPoint(x: x - 0.12, y: y + 0.02)
        return HandPoseSample(time: time, points: points)
    }

    @Test func heldOpenPalmFiresOnce() {
        var recognizer = HandGestureRecognizer()
        var fired: [HandGesture] = []
        for i in 0..<20 {
            let t = Double(i) * 0.1
            if let g = recognizer.process(hand(at: 0.5, fingersOpen: true, time: t), at: t) { fired.append(g) }
        }
        #expect(fired == [.openPalm])
    }

    /// On the iPad, Vision lost the hand every few frames, and a hold that had to
    /// be unbroken never fired.
    @Test func openPalmFiresThroughMissedFrames() {
        var recognizer = HandGestureRecognizer()
        var fired: [HandGesture] = []
        for i in 0..<12 {
            let t = Double(i) * 0.1
            let sample = i % 4 == 3 ? nil : hand(at: 0.5, fingersOpen: true, time: t)
            if let g = recognizer.process(sample, at: t) { fired.append(g) }
        }
        #expect(fired == [.openPalm])
    }

    @Test func threeStraightFingersAreAnOpenPalm() {
        var sample = hand(at: 0.5, fingersOpen: true, time: 0)
        sample.points[.littleTip] = nil
        #expect(HandGestureRecognizer.staticPose(sample) == .openPalm)
        #expect(HandGestureRecognizer().describe(nil) == "no hand")
    }

    /// Open palms first teach the recognizer which way is up.
    private func teachUp(_ recognizer: inout HandGestureRecognizer, rotate: Bool = false) -> [HandGesture] {
        (0..<8).compactMap { i in
            let t = Double(i) * 0.1
            let palm = hand(at: 0.5, fingersOpen: true, time: t)
            return recognizer.process(rotate ? rotated(palm) : palm, at: t)
        }
    }

    /// The same hand in an image turned upside down, as on the 3rd generation 11-inch iPad Pro.
    private func rotated(_ sample: HandPoseSample) -> HandPoseSample {
        HandPoseSample(time: sample.time, points: sample.points.mapValues { CGPoint(x: 1 - $0.x, y: 1 - $0.y) })
    }

    /// A palm that moves (waving, gesturing while talking) toggled the music.
    @Test func aMovingPalmDoesNotFire() {
        var recognizer = HandGestureRecognizer()
        var fired: [HandGesture] = []
        for i in 0..<15 {
            let t = Double(i) * 0.1
            if let g = recognizer.process(hand(at: 0.3 + CGFloat(i) * 0.03, fingersOpen: true, time: t), at: t) { fired.append(g) }
        }
        #expect(fired.isEmpty)
    }

    /// A small open hand, far away or resting, is not a palm raised toward the iPad.
    @Test func aSmallFarPalmDoesNotFire() {
        var recognizer = HandGestureRecognizer()
        var fired: [HandGesture] = []
        for i in 0..<15 {
            let t = Double(i) * 0.1
            let full = hand(at: 0.5, fingersOpen: true, time: t)
            let wrist = full.points[.wrist]!
            let small = HandPoseSample(time: t, points: full.points.mapValues {
                CGPoint(x: wrist.x + ($0.x - wrist.x) * 0.3, y: wrist.y + ($0.y - wrist.y) * 0.3)
            })
            if let g = recognizer.process(small, at: t) { fired.append(g) }
        }
        #expect(fired.isEmpty)
    }

    /// Closing the hand after showing a palm is nothing.
    @Test func aFistIsNothing() {
        var recognizer = HandGestureRecognizer()
        var fired = teachUp(&recognizer)
        for i in 0..<10 {
            let t = 2 + Double(i) * 0.1
            if let g = recognizer.process(hand(at: 0.5, fingersOpen: false, time: t), at: t) { fired.append(g) }
        }
        #expect(fired == [.openPalm])
    }

    @Test func anUpsideDownImageLearnsWhichWayIsUp() {
        var recognizer = HandGestureRecognizer()
        var fired = teachUp(&recognizer, rotate: true)
        // A closed hand moving afterwards is nothing.
        for i in 0..<6 {
            let t = 2 + Double(i) * 0.1
            let raised = hand(at: 0.5, y: 0.3 + CGFloat(i) * 0.08, fingersOpen: false, time: t)
            if let g = recognizer.process(rotated(raised), at: t), g != .openPalm { fired.append(g) }
        }
        #expect(fired == [.openPalm])
    }
}

/// A synthetic face tracking depth map (640 by 360, focal 382 px, as on the
/// 11-inch): a wall, a person, and a hand raised toward the iPad.
private struct PalmScene {
    static let width = 640
    static let height = 360
    static let focal = 382.0
    var meters = [Float](repeating: 3, count: width * height)

    /// Paints `inside` (meters across and down from the middle of the view, at `depth`) at `depth`, nearest wins.
    mutating func paint(at depth: Double, _ inside: (Double, Double) -> Double?) {
        for row in 0..<Self.height {
            for column in 0..<Self.width {
                let x = (Double(column) - Double(Self.width) / 2) * depth / Self.focal
                let y = (Double(row) - Double(Self.height) / 2) * depth / Self.focal
                guard let z = inside(x, y) else { continue }
                let index = row * Self.width + column
                meters[index] = min(meters[index], Float(z))
            }
        }
    }

    /// A head at `depth`, centered `x` across, with shoulders below: a face
    /// 16 by 22 cm and 4 cm deep, and around it the sides of the head, ears and
    /// hair, going 10 cm farther back, as a real head does.
    mutating func person(at depth: Double, x center: Double = 0) {
        paint(at: depth) { x, y in
            let dx = (x - center) / 0.08
            let dy = y / 0.11
            let r = (dx * dx + dy * dy).squareRoot()
            if r <= 1 { return depth + 0.04 * r * r }
            return r <= 1.35 ? depth + 0.04 + 0.1 * (r - 1) / 0.35 : nil
        }
        paint(at: depth + 0.12) { x, y in abs(x - center) <= 0.22 && y >= 0.12 ? depth + 0.12 : nil }
    }

    /// An open hand, flat toward the iPad: a 9 by 10 cm palm, four 1.8 cm
    /// fingers 8 cm long with gaps between them, and a forearm 6 cm wide that
    /// goes `slope` meters back for every meter down from the wrist.
    mutating func hand(at depth: Double, x center: Double = 0, y top: Double = -0.08, slope: Double = 0.6) {
        paint(at: depth) { x, y in
            let across = x - center
            let down = y - top
            if abs(across) <= 0.045 && down >= 0.08 && down <= 0.18 { return depth }
            if abs(across) <= 0.045 && down >= 0 && down < 0.08 {
                let slot = (across + 0.045) / 0.0225
                let within = slot - slot.rounded(.down)
                return within >= 0.1 && within <= 0.9 ? depth : nil
            }
            return nil
        }
        paint(at: depth) { x, y in
            abs(x - center) <= 0.03 && y - top > 0.18 && y - top <= 0.45 ? depth + slope * (y - top - 0.18) : nil
        }
    }

    var map: DepthMap {
        DepthMap(width: Self.width, height: Self.height, meters: meters, focalLength: Self.focal)
    }
}

@Suite struct DepthPalmTests {
    @Test func aPalmRaisedInFrontOfTheFaceIsAPalm() throws {
        var scene = PalmScene()
        scene.person(at: 0.75)
        scene.hand(at: 0.38)
        let result = DepthPalmDetector.detect(in: scene.map)
        let palm = try #require(result.palm, "\(result.description)")
        #expect(abs(palm.meters - 0.38) < 0.02)
        #expect(palm.clearance >= DepthPalmDetector.minimumClearance)
    }

    /// Kyle: the hand has to be clearly closer than everything else. A hand at
    /// the head's depth, beside it, has the head within reach.
    @Test func aHandBesideTheHeadIsNot() {
        var scene = PalmScene()
        scene.person(at: 0.6)
        scene.hand(at: 0.6, x: 0.25)
        let result = DepthPalmDetector.detect(in: scene.map)
        #expect(result.palm == nil)
    }

    /// Kyle: more than a foot closer. 25 cm in front of the face is not.
    @Test func aHandLessThanAFootInFrontOfTheFaceIsNot() {
        var scene = PalmScene()
        scene.person(at: 0.75)
        scene.hand(at: 0.5)
        #expect(DepthPalmDetector.detect(in: scene.map).palm == nil)
    }

    /// A hand raised on an upright forearm: the arm lies in the palm's plane.
    @Test func aPalmOnAnUprightForearmIsAPalm() throws {
        var scene = PalmScene()
        scene.person(at: 0.75)
        scene.hand(at: 0.38, slope: 0)
        let result = DepthPalmDetector.detect(in: scene.map)
        _ = try #require(result.palm, "\(result.description)")
    }

    /// An arm that runs back into the shoulders joins the hand to the body,
    /// and the body within a foot behind it still counts.
    @Test func anArmJoinedToTheBodyDoesNotExcuseTheBody() {
        var scene = PalmScene()
        scene.person(at: 0.6)
        scene.hand(at: 0.45, x: 0.2, slope: 1)
        let result = DepthPalmDetector.detect(in: scene.map)
        #expect(result.palm == nil)
    }

    /// A face leaning in is the nearest thing in view, but the head goes on around it.
    @Test func aFaceLeaningInIsNot() {
        var scene = PalmScene()
        scene.person(at: 0.35)
        #expect(DepthPalmDetector.detect(in: scene.map).palm == nil)
    }

    @Test func aPalmHeldStillFiresOnceOverDepthMaps() {
        var hold = PalmHold()
        // About five depth maps a second, as in the dark.
        let fired = stride(from: 0.0, through: 2.0, by: 0.2).filter { time in
            hold.note(isPalm: true, center: CGPoint(x: 0.5, y: 0.4), at: time)
        }
        #expect(fired.count == 1)
    }
}
