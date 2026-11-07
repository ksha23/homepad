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
