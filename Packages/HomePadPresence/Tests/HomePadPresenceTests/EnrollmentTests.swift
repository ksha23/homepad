import Foundation
import Testing
@testable import HomePadPresence

@Suite struct EnrollmentStepTests {
    @Test func coversTwoDistancesInUnderThirtySamples() {
        let steps = EnrollmentStep.allCases
        let total = steps.map(\.samplesNeeded).reduce(0, +)
        #expect(total == 24)
        #expect(steps.filter { $0.distance == .far } == [.sitBack, .sitBackTurn])
        // The far steps come last, so the near samples set the size to compare with.
        #expect(steps.suffix(2).allSatisfy { $0.distance == .far })
    }

    @Test func sidesSpanFifteenToFortyFiveDegrees() {
        let radians = Double.pi / 180
        #expect(!EnrollmentStep.sideA.matches(yaw: 12 * radians, pitch: 0, firstSide: nil))
        #expect(EnrollmentStep.sideA.matches(yaw: 30 * radians, pitch: 0, firstSide: nil))
        #expect(!EnrollmentStep.sideA.matches(yaw: 50 * radians, pitch: 0, firstSide: nil))
        #expect(EnrollmentStep.sideB.matches(yaw: -30 * radians, pitch: 0, firstSide: 0.4))
        #expect(!EnrollmentStep.sideB.matches(yaw: 30 * radians, pitch: 0, firstSide: 0.4))
        // Chin steps take some yaw, so they cover the diagonals too.
        #expect(EnrollmentStep.chinUp.matches(yaw: 15 * radians, pitch: -12 * radians, firstSide: nil))
    }
}

@Suite struct EnrollmentSampleFilterTests {
    private let identity = SyntheticFace.identity(for: UUID())
    private let radians = Double.pi / 180

    private func observation(
        yaw: Double = 0, pitch: Double = 0, width: Double = 0.3, distance: Double? = nil, live: Bool? = nil,
        luma: Double? = 0.5, faces: Int = 1, seed: UInt64? = nil, time: TimeInterval
    ) -> EnrollmentObservation {
        let liveness = live.map { LivenessResult(isLive: $0, reliefMeters: $0 ? 0.02 : 0.004, validFraction: 1, distanceMeters: distance) }
            ?? distance.map { LivenessResult(isLive: true, reliefMeters: 0.02, validFraction: 1, distanceMeters: $0) }
        let sample = FaceEmbeddingSample(
            embedding: SyntheticFace.sample(around: identity, noise: 0.04, seed: seed ?? UInt64(time * 100) + 1), liveness: liveness,
            yaw: yaw * radians, pitch: pitch * radians
        )
        return EnrollmentObservation(
            faceCount: faces, faceWidth: width, yaw: sample.yaw, pitch: sample.pitch, sample: sample, time: time, faceLuma: luma
        )
    }

    private func run(_ filter: inout EnrollmentSampleFilter, _ observation: EnrollmentObservation, _ step: EnrollmentStep,
                     liveness: Bool = false) -> EnrollmentSampleFilter.Verdict {
        let verdict = filter.evaluate(observation, step: step, requiresLiveness: liveness)
        if verdict == .accept { filter.keep(observation, for: step) }
        return verdict
    }

    @Test func hardRulesComeFirst() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(faces: 2, time: 0), .center) == .hint("Only one person at a time, please"))
        #expect(run(&filter, observation(width: 0.1, time: 0.2), .center) == .hint("Move a little closer"))
        #expect(run(&filter, observation(live: false, time: 0.4), .center, liveness: true) == .hint("Use your real face, not a photo"))
        #expect(run(&filter, observation(yaw: 20, time: 0.6), .center) == .hint("Look straight at the screen"))
        // Over a second later, so the turn back to the screen does not count as moving.
        #expect(run(&filter, observation(live: true, time: 2), .center, liveness: true) == .accept)
    }

    @Test func farStepsUseTheMeasuredDistance() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(distance: 0.8, time: 0), .center) == .hint("Move a little closer"))
        #expect(run(&filter, observation(distance: 0.45, time: 0.3), .center) == .accept)
        #expect(run(&filter, observation(width: 0.2, distance: 0.5, time: 1), .sitBack) == .hint("Sit back a little more"))
        #expect(run(&filter, observation(width: 0.12, distance: 1.3, time: 1.3), .sitBack) == .hint("Come a little closer"))
        #expect(run(&filter, observation(width: 0.14, distance: 0.85, time: 1.6), .sitBack) == .accept)
    }

    @Test func withoutDepthFarStepsCompareFaceSize() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(width: 0.3, time: 0), .center) == .accept)
        #expect(run(&filter, observation(width: 0.25, time: 1), .sitBack) == .hint("Sit back a little more"))
        #expect(run(&filter, observation(width: 0.08, time: 1.3), .sitBack) == .hint("Come a little closer"))
        #expect(run(&filter, observation(width: 0.16, time: 1.6), .sitBack) == .accept)
    }

    @Test func aFastTurnWaitsForStillness() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(yaw: 0, time: 0), .sideA) == .hint("Keep going"))
        // 20 degrees in a fifth of a second blurs the face.
        #expect(run(&filter, observation(yaw: 20, time: 0.2), .sideA) == .hint("Hold still"))
        #expect(run(&filter, observation(yaw: 22, time: 0.4), .sideA) == .accept)
    }

    @Test func darkFacesAreSkipped() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(luma: 0.03, time: 0), .center) == .hint("Find a little more light"))
        #expect(run(&filter, observation(luma: 0.99, time: 0.3), .center) == .hint("Move out of the bright light"))
        #expect(run(&filter, observation(luma: 0.3, time: 0.6), .center) == .accept)
    }

    @Test func samplesSpreadOverTheTurn() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(yaw: 18, time: 0), .sideA) == .accept)
        #expect(run(&filter, observation(yaw: 20, seed: 2, time: 0.3), .sideA) == .hint("Keep turning slowly"))
        #expect(run(&filter, observation(yaw: 24, seed: 3, time: 0.6), .sideA) == .accept)
    }

    @Test func nearCopiesAreSkipped() {
        var filter = EnrollmentSampleFilter()
        #expect(run(&filter, observation(seed: 7, time: 0), .center) == .accept)
        #expect(run(&filter, observation(seed: 7, time: 0.3), .center) == .hint("Move your head a little"))
        #expect(run(&filter, observation(seed: 8, time: 0.6), .center) == .accept)
    }

    @Test func qualityRulesRelaxRatherThanStall() {
        var filter = EnrollmentSampleFilter()
        var time = 0.0
        var verdicts: [EnrollmentSampleFilter.Verdict] = []
        // A dark room: every frame is too dark, but the pose is right.
        while time < 7 {
            verdicts.append(run(&filter, observation(luma: 0.03, seed: UInt64(time * 10) + 1, time: time), .center))
            time += 0.5
        }
        #expect(verdicts.first == .hint("Find a little more light"))
        #expect(verdicts.contains(.accept))
        #expect(filter.relaxedSteps == [.center])
    }

    @Test func theScriptedPersonFinishesEveryStep() {
        // Drives the filter like the simulator does, 0.35 s per frame.
        var filter = EnrollmentSampleFilter()
        var stepIndex = 0
        var inStep = 0
        var frame: UInt64 = 0
        let steps = EnrollmentStep.allCases
        while stepIndex < steps.count, frame < 200 {
            frame += 1
            let step = steps[stepIndex]
            let pose = SimulatedEnrollmentCapture.pose(for: step, frame: frame)
            let observation = observation(yaw: pose.yaw, pitch: pose.pitch, width: step.distance == .far ? 0.15 : 0.3,
                                          luma: nil, seed: frame, time: Double(frame) * 0.35)
            if run(&filter, observation, step) == .accept {
                inStep += 1
                if inStep == step.samplesNeeded {
                    stepIndex += 1
                    inStep = 0
                }
            }
        }
        #expect(stepIndex == steps.count)
        #expect(filter.kept.count == 24)
        #expect(filter.relaxedSteps.isEmpty)
        // Under a minute of frames.
        #expect(Double(frame) * 0.35 < 60)
    }
}

@Suite struct DepthLivenessDistanceTests {
    @Test func reportsTheMedianDepthOfTheFace() {
        let face: [Float] = (0..<81).map { index in
            let x = Double(index % 9) / 8 - 0.5
            let y = Double(index / 9) / 8 - 0.5
            return Float(0.8 + 0.16 * (x * x + y * y))
        }
        let result = DepthLiveness.evaluate(samples: face, columns: 9)
        let distance = result.distanceMeters ?? 0
        #expect(distance > 0.8 && distance < 0.85)
    }
}
