import CoreVideo
import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// The models load at launch, on a blank frame in the cameras' format.
@Suite struct RecognitionWarmUpTests {
    @Test func warmUpRunsOnABlankCameraFrame() throws {
        let buffer = try #require(FaceEmbedder.blankFrame(width: 640, height: 480))
        #expect(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        var readyAfter: TimeInterval?
        let report = FrameAnalyzer.warmUpModels(featurePrint: true, detectors: true, hands: true) { readyAfter = $0 }
        #expect(readyAfter == report.featurePrint)
        #expect(report.hands != nil && report.faces != nil)
        #expect(report.description.contains("feature print"))
    }

    @Test func detectorsAloneLeaveRecognitionOutOfTheReport() {
        var ready = false
        let report = FrameAnalyzer.warmUpModels(featurePrint: false, detectors: true, hands: false) { _ in ready = true }
        #expect(!ready)
        #expect(report.featurePrint == nil && report.hands == nil)
        #expect(report.description.contains("faces"))
    }

    @Test func detectorsCanMoveBetweenTheCPUAndVisionsChoice() throws {
        let buffer = try #require(FaceEmbedder.blankFrame(width: 640, height: 480))
        let detectors = VisionDetectors()
        detectors.runOnCPU(true)
        detectors.warmUp(on: buffer, faces: true, hands: true)
        detectors.runOnCPU(false)
        detectors.warmUp(on: buffer, faces: true, hands: true)
    }
}

@Suite struct RecognitionSampleGateTests {
    /// Frame capture times at `fps`, with a little timing jitter like real cameras.
    private func frameTimes(count: Int, fps: Double = 10) -> [TimeInterval] {
        (0..<count).map { Double($0) / fps + ($0.isMultiple(of: 2) ? 0.003 : -0.003) }
    }

    @Test func fastIntervalSamplesEverySecondFrameAtTenFPS() {
        var gate = RecognitionSampleGate()
        var sampled: [Int] = []
        for (index, time) in frameTimes(count: 20).enumerated()
        where gate.shouldSample(at: time, wanted: true, interval: 0.2, hasDepth: true, needsDepth: true) {
            gate.recordSample(at: time)
            sampled.append(index)
        }
        #expect(sampled == Array(stride(from: 0, to: 20, by: 2)))
    }

    @Test func slowIntervalSamplesEveryFifthFrameAtTenFPS() {
        var gate = RecognitionSampleGate()
        var sampled: [Int] = []
        for (index, time) in frameTimes(count: 20).enumerated()
        where gate.shouldSample(at: time, wanted: true, interval: 0.5, hasDepth: false, needsDepth: false) {
            gate.recordSample(at: time)
            sampled.append(index)
        }
        #expect(sampled == [0, 5, 10, 15])
    }

    /// Answers for a run of frames. `#expect` cannot call mutating methods itself.
    private func answers(
        _ gate: inout RecognitionSampleGate, _ frames: [(time: TimeInterval, wanted: Bool, depth: Bool)], needsDepth: Bool = true
    ) -> [Bool] {
        frames.map { gate.shouldSample(at: $0.time, wanted: $0.wanted, interval: 0.2, hasDepth: $0.depth, needsDepth: needsDepth) }
    }

    @Test func aDueSampleWaitsForTheNextFrameWithDepth() {
        var gate = RecognitionSampleGate()
        // Face tracking just started: the first frame has no depth yet.
        let due = answers(&gate, [(10.0, true, false), (10.1, true, true)])
        #expect(due == [false, true])
        let waited = gate.recordSample(at: 10.1) ?? 0
        #expect(abs(waited - 0.1) < 1e-9)
    }

    @Test func aSampleWithDepthRightAwayReportsNoWait() {
        var gate = RecognitionSampleGate()
        let due = answers(&gate, [(10, true, true)])
        let waited = gate.recordSample(at: 10)
        #expect(due == [true])
        #expect(waited == nil)
    }

    @Test func theWaitForDepthIsBounded() {
        var gate = RecognitionSampleGate(maxDepthWait: 0.5)
        // Depth stays away: after 0.5 s the sample goes ahead, and the service decides.
        let due = answers(&gate, [10.0, 10.1, 10.2, 10.3, 10.4, 10.5].map { ($0, true, false) })
        #expect(due == [false, false, false, false, false, true])
        let waited = gate.recordSample(at: 10.5) ?? 0
        #expect(abs(waited - 0.5) < 1e-9)
    }

    @Test func cameraWithoutDepthDoesNotWait() {
        var gate = RecognitionSampleGate()
        let due = answers(&gate, [(10, true, false)], needsDepth: false)
        #expect(due == [true])
    }

    @Test func stoppingRecognitionClearsTheWait() {
        var gate = RecognitionSampleGate(maxDepthWait: 0.5)
        // The face left the range at 10.1, so the old wait must not count later.
        let due = answers(&gate, [(10, true, false), (10.1, false, false), (12, true, false), (12.5, true, false)])
        #expect(due == [false, false, false, true])
    }
}

@Suite struct RecognitionCadenceTests {
    private let member = UUID()
    private let t0 = Date(timeIntervalSince1970: 4_000_000)

    @Test func fastAtTheStartOfALook() {
        #expect(RecognitionCadence().interval(at: t0, fastInterval: 0.2) == 0.2)
    }

    @Test func aFaceThatKeepsNotMatchingSlowsDown() {
        var cadence = RecognitionCadence()
        var time = t0
        while time.timeIntervalSince(t0) < 2.9 {
            cadence.record(.unknown(bestScore: 0.6), at: time)
            #expect(cadence.interval(at: time, fastInterval: 0.2) == 0.2)
            time += 0.2
        }
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 3)
        #expect(cadence.interval(at: t0 + 3, fastInterval: 0.2) == 0.5)
    }

    @Test func aMatchSpeedsUpAgain() {
        var cadence = RecognitionCadence()
        cadence.record(.unknown(bestScore: 0.6), at: t0)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 1.5)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 3.5)
        #expect(cadence.interval(at: t0 + 3.5, fastInterval: 0.2) == 0.5)
        cadence.record(.member(member, score: 0.86), at: t0 + 4)
        #expect(cadence.interval(at: t0 + 4, fastInterval: 0.2) == 0.2)
        // A miss after the burst goes back to the slow rate.
        cadence.record(.spoof, at: t0 + 4.2)
        #expect(cadence.interval(at: t0 + 4.2, fastInterval: 0.2) == 0.5)
    }

    @Test func aPauseStartsANewBurst() {
        var cadence = RecognitionCadence()
        cadence.record(.unknown(bestScore: 0.6), at: t0)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 1.8)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 3.6)
        #expect(cadence.interval(at: t0 + 3.6, fastInterval: 0.2) == 0.5)
        // The face turned away for a while: the next look starts fast.
        #expect(cadence.interval(at: t0 + 6, fastInterval: 0.2) == 0.2)
        cadence.record(nil, at: t0 + 6)
        #expect(cadence.interval(at: t0 + 6.2, fastInterval: 0.2) == 0.2)
    }

    @Test func resetStartsOver() {
        var cadence = RecognitionCadence()
        cadence.record(.unknown(bestScore: 0.6), at: t0)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 1.8)
        cadence.record(.unknown(bestScore: 0.6), at: t0 + 3.6)
        cadence.reset()
        #expect(cadence.interval(at: t0 + 3.6, fastInterval: 0.2) == 0.2)
    }
}

@Suite struct RecognitionTimelineTests {
    private let t0 = Date(timeIntervalSince1970: 4_100_000)

    @Test func firstFaceIsNotedOncePerLook() {
        var timeline = RecognitionTimeline()
        let first = timeline.noteFace(at: t0)
        let again = timeline.noteFace(at: t0 + 0.5)
        // A sighting that never led to a sample is forgotten after a gap.
        let afterGap = timeline.noteFace(at: t0 + 10)
        let firstSample = timeline.noteSample(skipped: false, at: t0 + 11)
        // Once sampling started, the look keeps its first face.
        let later = timeline.noteFace(at: t0 + 30)
        #expect([first, again, afterGap, firstSample, later] == [true, false, true, true, false])
        #expect(timeline.firstFaceAt == t0 + 10)
    }

    @Test func summaryCountsSamplesAndSeconds() {
        var timeline = RecognitionTimeline()
        _ = timeline.noteFace(at: t0)
        let first = timeline.noteSample(skipped: true, at: t0 + 2.5)
        let second = timeline.noteSample(skipped: false, at: t0 + 2.6)
        #expect(first && !second)
        _ = timeline.noteSample(skipped: false, at: t0 + 2.8)
        _ = timeline.noteSample(skipped: false, at: t0 + 3.0)
        _ = timeline.noteSample(skipped: false, at: t0 + 3.2)
        #expect(timeline.summary(at: t0 + 3.2) == "after 5 samples (1 skipped) in 0.70 s, 3.20 s after the first face")
        timeline.reset()
        #expect(timeline.firstFaceAt == nil && timeline.samples == 0)
    }
}

/// The service ties the cadence to its votes: fast while a match is likely,
/// and stricter settings still need more and better votes.
@MainActor @Suite struct RecognitionSpeedTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.speed.\(UUID())")!))
    private let member = UUID()
    /// Now, because the 30 s refresh compares against the clock.
    private let t0 = Date()
    private let live = LivenessResult(isLive: true, reliefMeters: 0.025, validFraction: 1)

    private func makeService() throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        let service = FaceRecognitionService(services: services, store: nil)
        let identity = SyntheticFace.identity(for: member)
        try service.saveEnrollment(memberID: member, embeddings: (1...5).map {
            SyntheticFace.sample(around: identity, noise: 0.04, seed: UInt64($0))
        }, revision: 0)
        return service
    }

    private func memberSample(_ seed: UInt64) -> FaceEmbeddingSample {
        FaceEmbeddingSample(embedding: SyntheticFace.sample(around: SyntheticFace.identity(for: member), noise: 0.04, seed: seed),
                            liveness: live)
    }

    private func strangerSample() -> FaceEmbeddingSample {
        FaceEmbeddingSample(embedding: SyntheticFace.identity(for: UUID()), liveness: live)
    }

    @Test func fourFastSamplesRecognizeInUnderASecond() throws {
        let service = try makeService()
        var time = t0
        for seed in 1...4 {
            #expect(service.confirmedMemberID == nil)
            service.consider(memberSample(UInt64(100 + seed)), requireLiveness: true, at: time)
            time += service.sampleInterval(at: time)
        }
        #expect(service.confirmedMemberID == member)
        #expect(service.wantsEmbeddings == false)
    }

    @Test func aGuestIsSampledSlowlyAfterTheBurst() throws {
        let service = try makeService()
        var time = t0
        while time.timeIntervalSince(t0) < 4 {
            service.consider(strangerSample(), requireLiveness: true, at: time)
            time += service.sampleInterval(at: time)
        }
        #expect(service.confirmedMemberID == nil)
        #expect(service.sampleInterval(at: time) == 0.5)
        service.presenceEnded()
        #expect(service.sampleInterval(at: time) == 0.2)
    }

    @Test func stricterSettingsStayStricter() {
        let levels: [RecognitionStrictness] = [.relaxed, .standard, .strict]
        for (looser, stricter) in zip(levels, levels.dropFirst()) {
            #expect(looser.matcher.acceptThreshold < stricter.matcher.acceptThreshold)
            #expect(looser.matcher.margin < stricter.matcher.margin)
            #expect(looser.voter.requiredVotes < stricter.voter.requiredVotes)
            // The shortest time the votes can cover grows with strictness too.
            let looserSpan = Double(looser.voter.requiredVotes - 1) * looser.fastSampleInterval
            let stricterSpan = Double(stricter.voter.requiredVotes - 1) * stricter.fastSampleInterval
            #expect(looserSpan < stricterSpan)
        }
    }

    @Test func strictKeepsTheSlowRate() throws {
        let service = try makeService()
        services.settings[PresenceSettings.recognitionStrictness] = .strict
        #expect(service.sampleInterval(at: t0) == 0.5)
        services.settings[PresenceSettings.recognitionStrictness] = .standard
        #expect(service.sampleInterval(at: t0) == 0.2)
    }
}
