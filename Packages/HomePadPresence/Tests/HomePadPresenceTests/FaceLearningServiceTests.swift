import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// Learning from use inside the recognition service: it starts with a confirmed
/// recognition on one face track, keeps learned samples apart and capped,
/// persists them next to the template, and clears them on reset and re-enrollment.
@MainActor @Suite struct FaceLearningServiceTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.learning.\(UUID())")!))
    private let alice = UUID()
    private let bob = UUID()
    private let track = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 9000)

    private func makeService(store: FaceTemplateStore? = nil, policy: FaceLearningPolicy = FaceLearningPolicy()) throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        let service = FaceRecognitionService(services: services, store: store, learningPolicy: policy)
        try service.saveEnrollment(memberID: alice, embeddings: [LearningVectors.axis(0)])
        return service
    }

    /// Four matching samples on `track`, 0.2 s apart: Standard confirms on the last.
    private func recognize(_ service: FaceRecognitionService, on track: UUID?, from start: Date) {
        for index in 0..<4 {
            let sample = LearningVectors.sample(LearningVectors.probe(0.9, toward: 10 + index), track: track)
            service.consider(sample, requireLiveness: true, at: start + Double(index) * 0.2)
        }
    }

    private func temporaryStore() -> FaceTemplateStore {
        FaceTemplateStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("learning-tests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func learnsOnTheTrackThatWasRecognized() throws {
        let service = try makeService()
        recognize(service, on: track, from: t0)
        #expect(service.confirmedMemberID == alice)
        #expect(service.wantsLearningSamples(at: t0 + 2))
        #expect(service.isSamplingOnlyToLearn(at: t0 + 2))
        #expect(service.sampleInterval(at: t0 + 2) == service.learningPolicy.sampleInterval)

        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: track), requireLiveness: true, at: t0 + 2)
        #expect(service.learnedCount(for: alice) == 1)
        // Too soon after the last one.
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 21), track: track), requireLiveness: true, at: t0 + 4)
        #expect(service.learnedCount(for: alice) == 1)
        // The enrolled template is untouched.
        #expect(service.templates[alice]?.embeddings == [LearningVectors.axis(0)])
    }

    @Test func aRecognitionWithoutAFaceTrackDoesNotLearn() throws {
        let service = try makeService()
        recognize(service, on: nil, from: t0)
        #expect(service.confirmedMemberID == alice)
        #expect(!service.wantsLearningSamples(at: t0 + 2))
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: nil), requireLiveness: true, at: t0 + 2)
        #expect(service.learnedCount(for: alice) == 0)
    }

    @Test func aBreakInTheTrackStopsLearning() throws {
        let service = try makeService()
        recognize(service, on: track, from: t0)
        service.noteFaceTrack(nil)
        service.noteFaceTrack(track)
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: track), requireLiveness: true, at: t0 + 2)
        #expect(service.learnedCount(for: alice) == 0)
        #expect(!service.wantsLearningSamples(at: t0 + 2))
    }

    @Test func learnedSamplesWidenMatchingWithTheSameThreshold() throws {
        let service = try makeService()
        let matcher = RecognitionStrictness.standard.matcher
        let learned = LearningVectors.probe(0.78, toward: 20)
        // Close to the learned sample, 0.76 to the enrollment.
        let later = FaceMatcher.normalized(zip(learned, LearningVectors.axis(30)).map { $0 * 0.97 + $1 * 0.24 })
        #expect(matcher.match(later, against: service.matchSet).memberID == nil)
        recognize(service, on: track, from: t0)
        service.consider(LearningVectors.sample(learned, track: track), requireLiveness: true, at: t0 + 2)
        #expect(matcher.match(later, against: service.matchSet).memberID == alice)
        #expect(matcher.match(later, against: Array(service.templates.values)).memberID == nil)
    }

    @Test func samplesTakenToLearnDoNotVote() throws {
        let service = try makeService()
        try service.saveEnrollment(memberID: bob, embeddings: [LearningVectors.axis(1)])
        recognize(service, on: track, from: t0)
        for index in 0..<6 {
            let bobLike = LearningVectors.probe(0.95, toward: 40 + index, base: 1)
            service.consider(LearningVectors.sample(bobLike, track: track), requireLiveness: true, at: t0 + 2 + Double(index) * 0.2)
        }
        #expect(service.confirmedMemberID == alice)
        #expect(service.learnedCount(for: alice) == 0)
    }

    @Test func keepsAtMostTheCapAndRollsOutTheOldest() throws {
        var policy = FaceLearningPolicy()
        policy.capPerMember = 3
        policy.perTrackLimit = 10
        let service = try makeService(policy: policy)
        recognize(service, on: track, from: t0)
        let learned = (0..<5).map { LearningVectors.probe(0.78, toward: 20 + $0) }
        for (index, embedding) in learned.enumerated() {
            service.consider(LearningVectors.sample(embedding, track: track), requireLiveness: true, at: t0 + 2 + Double(index) * policy.minimumSpacing)
        }
        #expect(service.learnedCount(for: alice) == 3)
        #expect(service.learnedSamples[alice]?.embeddings == Array(learned.suffix(3)))
    }

    @Test func learnedSamplesPersistNextToTheTemplate() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let service = try makeService(store: store)
        let templateFile = store.directory.appendingPathComponent("\(alice.uuidString).json")
        let enrolledBytes = try Data(contentsOf: templateFile)
        recognize(service, on: track, from: t0)
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: track), requireLiveness: true, at: t0 + 2)
        #expect(service.learnedCount(for: alice) == 1)
        // Learning never rewrites the enrolled template file.
        #expect(try Data(contentsOf: templateFile) == enrolledBytes)

        let reloaded = FaceRecognitionService(services: services, store: store)
        reloaded.load()
        #expect(reloaded.learnedCount(for: alice) == 1)
        #expect(reloaded.templates[alice]?.embeddings == [LearningVectors.axis(0)])
        #expect(reloaded.matchSet.first?.embeddings.count == 2)
    }

    @Test func resetForgetsOnlyWhatWasLearned() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let service = try makeService(store: store)
        recognize(service, on: track, from: t0)
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: track), requireLiveness: true, at: t0 + 2)
        service.resetLearned(memberID: alice)
        #expect(service.learnedCount(for: alice) == 0)
        #expect(service.hasEnrollment(alice))
        #expect(try store.loadLearned().isEmpty)
        #expect(service.matchSet.first?.embeddings.count == 1)
    }

    @Test func reEnrollingAndDeletingClearWhatWasLearned() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let service = try makeService(store: store)
        recognize(service, on: track, from: t0)
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 20), track: track), requireLiveness: true, at: t0 + 2)
        try service.saveEnrollment(memberID: alice, embeddings: [LearningVectors.axis(0)])
        #expect(service.learnedCount(for: alice) == 0)
        #expect(try store.loadLearned().isEmpty)

        service.presenceEnded()
        recognize(service, on: track, from: t0 + 10)
        service.consider(LearningVectors.sample(LearningVectors.probe(0.78, toward: 21), track: track), requireLiveness: true, at: t0 + 12)
        #expect(try store.loadLearned().count == 1)
        service.deleteEnrollment(memberID: alice)
        #expect(service.learnedCount(for: alice) == 0)
        #expect(try store.loadLearned().isEmpty)
        #expect(try store.loadAll().isEmpty)
    }

    @Test func learnedFilesDoNotLoadAsTemplates() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(FaceTemplate(memberID: alice, embeddings: [LearningVectors.axis(0)], featurePrintRevision: 0, createdAt: t0))
        let sample = LearnedFaceSample(embedding: LearningVectors.axis(2), learnedAt: t0, enrolledScore: 0.75, reliefMeters: 0.014)
        try store.saveLearned(LearnedFaceSamples(memberID: alice, featurePrintRevision: 0, samples: [sample]))
        #expect(try store.loadAll().count == 1)
        #expect(try store.loadLearned().first?.samples == [sample])
    }
}
