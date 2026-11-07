import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

@Suite struct FaceMatcherTests {
    private let alice = UUID()
    private let bob = UUID()

    private func template(_ id: UUID, samples: Int = 5) -> FaceTemplate {
        let identity = SyntheticFace.identity(for: id)
        let embeddings = (0..<samples).map { SyntheticFace.sample(around: identity, noise: 0.04, seed: UInt64($0 + 1)) }
        return FaceTemplate(memberID: id, embeddings: embeddings, featurePrintRevision: 0, createdAt: Date())
    }

    @Test func cosineBasics() {
        #expect(abs(FaceMatcher.cosine([1, 0], [1, 0]) - 1) < 1e-6)
        #expect(abs(FaceMatcher.cosine([1, 0], [0, 1])) < 1e-6)
        #expect(FaceMatcher.cosine([1, 0], [1, 0, 0]) == 0)
    }

    @Test func matchesTheRightMember() {
        let matcher = FaceMatcher(acceptThreshold: 0.8, margin: 0.04)
        let probe = SyntheticFace.sample(around: SyntheticFace.identity(for: alice), noise: 0.04, seed: 99)
        let decision = matcher.match(probe, against: [template(alice), template(bob)])
        #expect(decision.memberID == alice)
    }

    @Test func rejectsStrangers() {
        let matcher = FaceMatcher(acceptThreshold: 0.8, margin: 0.04)
        let stranger = SyntheticFace.identity(for: UUID())
        let decision = matcher.match(stranger, against: [template(alice), template(bob)])
        #expect(decision.memberID == nil)
        #expect((decision.score ?? 1) < 0.8)
    }

    @Test func requiresMarginOverRunnerUp() throws {
        // Two members with nearly identical templates: a probe between them is ambiguous.
        let base = SyntheticFace.identity(for: alice)
        let twinA = FaceTemplate(memberID: alice, embeddings: [base], featurePrintRevision: 0, createdAt: Date())
        let twinB = FaceTemplate(memberID: bob, embeddings: [SyntheticFace.sample(around: base, noise: 0.01, seed: 7)],
                                 featurePrintRevision: 0, createdAt: Date())
        let matcher = FaceMatcher(acceptThreshold: 0.8, margin: 0.04)
        let decision = matcher.match(base, against: [twinA, twinB])
        #expect(decision.memberID == nil)
        let score = try #require(decision.score)
        #expect(score > 0.99)
        // Without a margin requirement it would accept.
        #expect(FaceMatcher(acceptThreshold: 0.8, margin: 0).match(base, against: [twinA, twinB]).memberID == alice)
    }

    @Test func noTemplatesMeansUnknown() {
        #expect(FaceMatcher(acceptThreshold: 0.8, margin: 0.04).match([1, 0], against: []) == .unknown(bestScore: 0))
    }
}

@Suite struct RecognitionVoterTests {
    private let alice = UUID()
    private let bob = UUID()
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    @Test func confirmsAfterEnoughVotes() {
        var voter = RecognitionVoter(windowSize: 7, requiredVotes: 4)
        for i in 0..<3 {
            #expect(voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(Double(i) * 0.4)) == nil)
        }
        #expect(voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(1.2)) == alice)
    }

    @Test func unknownAndSpoofVotesDelayConfirmation() {
        var voter = RecognitionVoter(windowSize: 5, requiredVotes: 4)
        let decisions: [MatchDecision] = [.member(alice, score: 0.9), .spoof, .unknown(bestScore: 0.5), .member(alice, score: 0.9), .member(alice, score: 0.9)]
        var result: UUID?
        for (i, decision) in decisions.enumerated() { result = voter.add(decision, at: t0.addingTimeInterval(Double(i) * 0.3)) }
        #expect(result == nil)
        // Good votes push the spoof and the unknown out of the 5-slot window.
        #expect(voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(1.8)) == nil)
        #expect(voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(2.1)) == alice)
    }

    @Test func competingMembersBlockConfirmation() {
        var voter = RecognitionVoter(windowSize: 8, requiredVotes: 4)
        var result: UUID?
        for i in 0..<8 {
            let id = i.isMultiple(of: 2) ? alice : bob
            result = voter.add(.member(id, score: 0.85), at: t0.addingTimeInterval(Double(i) * 0.3))
        }
        #expect(result == nil)
    }

    @Test func oldVotesExpire() {
        var voter = RecognitionVoter(windowSize: 7, requiredVotes: 3, maxAge: 4)
        _ = voter.add(.member(alice, score: 0.9), at: t0)
        _ = voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(0.5))
        // The first two are stale by now, so a third does not confirm.
        #expect(voter.add(.member(alice, score: 0.9), at: t0.addingTimeInterval(10)) == nil)
    }

    @Test func endToEndWithSyntheticEmbeddings() {
        let template = FaceTemplate(
            memberID: alice,
            embeddings: (1...5).map { SyntheticFace.sample(around: SyntheticFace.identity(for: alice), noise: 0.05, seed: UInt64($0)) },
            featurePrintRevision: 0, createdAt: Date()
        )
        let strict = RecognitionStrictness.standard
        var voter = strict.voter
        var confirmed: UUID?
        for i in 0..<strict.voter.requiredVotes {
            let probe = SyntheticFace.sample(around: SyntheticFace.identity(for: alice), noise: 0.05, seed: UInt64(100 + i))
            confirmed = voter.add(strict.matcher.match(probe, against: [template]), at: t0.addingTimeInterval(Double(i) * 0.4))
        }
        #expect(confirmed == alice)
    }
}

@Suite struct DepthLivenessTests {
    /// A 9x9 grid over a face 0.6 m away.
    private func grid(_ depth: (Double, Double) -> Double) -> [Float] {
        (0..<9).flatMap { row in (0..<9).map { column in
            Float(depth(Double(column) / 8 - 0.5, Double(row) / 8 - 0.5))
        } }
    }

    @Test func flatPhotoIsRejectedEvenWhenTilted() {
        let photo = grid { x, y in 0.6 + 0.08 * x + 0.03 * y }
        let result = DepthLiveness.evaluate(samples: photo, columns: 9)
        #expect(result.isLive == false)
        #expect(result.reliefMeters < 0.002)
    }

    @Test func curvedFaceIsAccepted() {
        // A dome with the nose about 4 cm closer than the edges.
        let face = grid { x, y in 0.6 + 0.08 * (x * x + y * y) * 2 }
        let result = DepthLiveness.evaluate(samples: face, columns: 9)
        #expect(result.isLive)
        #expect(result.validFraction == 1)
    }

    @Test func sparseDepthIsNotLive() {
        var face = grid { x, y in 0.6 + 0.16 * (x * x + y * y) }
        for i in face.indices where i % 3 != 0 { face[i] = .nan }
        let result = DepthLiveness.evaluate(samples: face, columns: 9)
        #expect(result.validFraction < DepthLiveness.minimumValidFraction)
        #expect(result.isLive == false)
    }
}

/// TrueDepth measures depth on only some frames, so a passed liveness check
/// covers the next few seconds of samples, and a flat face ends that.
@MainActor @Suite struct LivenessCarryTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.carry.\(UUID())")!))
    private let member = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 5000)
    private let live = LivenessResult(isLive: true, reliefMeters: 0.025, validFraction: 1)
    private let flat = LivenessResult(isLive: false, reliefMeters: 0.002, validFraction: 1)

    private func makeService() throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        let service = FaceRecognitionService(services: services, store: nil)
        let identity = SyntheticFace.identity(for: member)
        try service.saveEnrollment(memberID: member, embeddings: (1...5).map {
            SyntheticFace.sample(around: identity, noise: 0.04, seed: UInt64($0))
        }, revision: 0)
        return service
    }

    private func sample(_ seed: UInt64, _ liveness: LivenessResult?) -> FaceEmbeddingSample {
        FaceEmbeddingSample(embedding: SyntheticFace.sample(around: SyntheticFace.identity(for: member), noise: 0.04, seed: seed),
                            liveness: liveness)
    }

    @Test func samplesWithoutDepthNeedARecentLiveCheck() throws {
        let service = try makeService()
        for i in 0..<7 {
            service.consider(sample(UInt64(100 + i), nil), requireLiveness: true, at: t0.addingTimeInterval(Double(i) * 0.4))
        }
        #expect(service.confirmedMemberID == nil)
    }

    @Test func oneLiveCheckCoversTheNextFewSamples() throws {
        let service = try makeService()
        service.consider(sample(100, live), requireLiveness: true, at: t0)
        for i in 1...3 {
            service.consider(sample(UInt64(100 + i), nil), requireLiveness: true, at: t0.addingTimeInterval(Double(i) * 0.4))
        }
        #expect(service.confirmedMemberID == member)
    }

    @Test func aFlatFaceEndsTheCarry() throws {
        let service = try makeService()
        service.consider(sample(100, live), requireLiveness: true, at: t0)
        service.consider(sample(101, flat), requireLiveness: true, at: t0.addingTimeInterval(0.4))
        for i in 2...6 {
            service.consider(sample(UInt64(100 + i), nil), requireLiveness: true, at: t0.addingTimeInterval(Double(i) * 0.4))
        }
        #expect(service.confirmedMemberID == nil)
    }

    @Test func theCarryRunsOut() throws {
        let service = try makeService()
        service.consider(sample(100, live), requireLiveness: true, at: t0)
        for i in 1...6 {
            service.consider(sample(UInt64(100 + i), nil), requireLiveness: true, at: t0.addingTimeInterval(3.5 + Double(i) * 0.4))
        }
        #expect(service.confirmedMemberID == nil)
    }
}
