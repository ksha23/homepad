import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// A stranger takes several clean samples far from everyone, and anything less
/// clean moves nothing.
@Suite struct StrangerVerdictTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 7000)
    private let far = MatchDecision.unknown(bestScore: 0.40)

    private func clean() -> FaceEmbeddingSample { LearningVectors.sample(LearningVectors.axis(5), track: nil) }

    @Test func fourCleanLowSamplesInARowMakeAStranger() {
        var verdict = StrangerVerdict()
        let results = (0..<4).map { verdict.add(far, sample: clean(), at: t0 + Double($0) * 0.3) }
        #expect(results == [false, false, false, true])
    }

    @Test func lowQualitySamplesNeverCount() {
        var verdict = StrangerVerdict()
        let twoFaces = LearningVectors.sample(LearningVectors.axis(5), track: nil, faces: 2)
        let noDepth = LearningVectors.sample(LearningVectors.axis(5), track: nil, liveness: nil)
        let background = LearningVectors.sample(
            LearningVectors.axis(5), track: nil, liveness: LivenessResult(isLive: true, reliefMeters: 0.6, validFraction: 1)
        )
        let patchy = LearningVectors.sample(
            LearningVectors.axis(5), track: nil, liveness: LivenessResult(isLive: true, reliefMeters: 0.02, validFraction: 0.6)
        )
        for (index, sample) in [twoFaces, noDepth, background, patchy, twoFaces, noDepth].enumerated() {
            let isStranger = verdict.add(far, sample: sample, at: t0 + Double(index) * 0.3)
            #expect(!isStranger)
        }
        #expect(verdict.count == 0)
    }

    @Test func aMatchOrAMiddlingScoreStartsOver() {
        var verdict = StrangerVerdict()
        for index in 0..<3 { _ = verdict.add(far, sample: clean(), at: t0 + Double(index) * 0.3) }
        let afterMiddling = verdict.add(.unknown(bestScore: 0.62), sample: clean(), at: t0 + 1)
        #expect(!afterMiddling)
        #expect(verdict.count == 0)
        for index in 0..<3 { _ = verdict.add(far, sample: clean(), at: t0 + 2 + Double(index) * 0.3) }
        let afterMatch = verdict.add(.member(UUID(), score: 0.85), sample: clean(), at: t0 + 3)
        #expect(!afterMatch)
        #expect(verdict.count == 0)
    }
}

/// Recognition hands the household's session to whoever steps in front:
/// another member on their own votes, Guest for a confident stranger, and
/// nothing for a face it cannot judge.
@MainActor @Suite struct SessionHandoffTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.handoff.\(UUID())")!))
    private let alice = HouseholdMember(name: "Alice")
    private let bob = HouseholdMember(name: "Bob")
    private let t0 = Date()

    private func makeService() throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        services.household.add(alice)
        services.household.add(bob)
        let service = FaceRecognitionService(services: services, store: nil)
        try service.saveEnrollment(memberID: alice.id, embeddings: [LearningVectors.axis(0)])
        try service.saveEnrollment(memberID: bob.id, embeddings: [LearningVectors.axis(1)])
        service.updateSensing(isWatching: true, isSomeonePresent: true, at: t0)
        return service
    }

    /// One analyzed frame with one tracked face, then a sample of it.
    private func show(_ embedding: [Float], on track: UUID, to service: FaceRecognitionService,
                      at time: Date, faces: Int = 1) {
        service.noteFaces(count: faces, track: faces == 1 ? track : nil, at: time)
        let sample = LearningVectors.sample(embedding, track: faces == 1 ? track : nil, faces: faces)
        service.consider(sample, requireLiveness: true, at: time)
    }

    private func aliceSignedIn() throws -> FaceRecognitionService {
        let service = try makeService()
        let track = UUID()
        for index in 0..<4 { show(LearningVectors.probe(0.9, toward: 10 + index), on: track, to: service, at: t0 + Double(index) * 0.2) }
        #expect(services.household.session.mode == .recognized(alice.id))
        return service
    }

    @Test func anotherMemberTakesOverOnTheirOwnVotes() throws {
        let service = try aliceSignedIn()
        let track = UUID()
        let start = t0 + 2
        for index in 0..<3 { show(LearningVectors.probe(0.9, toward: 20 + index, base: 1), on: track, to: service, at: start + Double(index) * 0.2) }
        #expect(services.household.activeMemberID == alice.id)
        show(LearningVectors.probe(0.9, toward: 23, base: 1), on: track, to: service, at: start + 0.6)
        #expect(services.household.session.mode == .recognized(bob.id))
    }

    @Test func aConfidentStrangerDropsToGuest() throws {
        let service = try aliceSignedIn()
        let track = UUID()
        for index in 0..<4 { show(LearningVectors.axis(5 + index), on: track, to: service, at: t0 + 2 + Double(index) * 0.2) }
        #expect(services.household.session.mode == .guest)
        #expect(!services.household.isPersonalContentUnlocked)
    }

    @Test func aFaceTooDarkToTellChangesNothing() throws {
        let service = try aliceSignedIn()
        // The owner's face in a dark room before the screen lights it scored
        // under the stranger ceiling. Too dark a crop is no evidence at all.
        let track = UUID()
        for index in 0..<8 {
            service.noteFaces(count: 1, track: track, at: t0 + 2 + Double(index) * 0.2)
            var sample = LearningVectors.sample(LearningVectors.axis(5 + index), track: track)
            sample.cropLuma = 0.05
            service.consider(sample, requireLiveness: true, at: t0 + 2 + Double(index) * 0.2)
        }
        #expect(services.household.session.mode == .recognized(alice.id))
    }

    @Test func aFaceItCannotJudgeChangesNothing() throws {
        let service = try aliceSignedIn()
        // Two faces in view: the nearest is far from everyone, but never clean enough.
        let track = UUID()
        for index in 0..<8 { show(LearningVectors.axis(5 + index), on: track, to: service, at: t0 + 2 + Double(index) * 0.2, faces: 2) }
        #expect(services.household.session.mode == .recognized(alice.id))
        #expect(service.lookIdentity == .unsure)
    }
}
