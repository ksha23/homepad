import Foundation
import HomePadCore
import simd
import Testing
@testable import HomePadPresence

/// A synthetic face mesh: an ellipsoid with a nose, sized by `width`.
enum SyntheticMesh {
    static func vertices(width: Float = 0.14, noseLength: Float = 0.03, count: Int = 1220) -> [SIMD3<Float>] {
        (0..<count).map { index in
            let u = Float(index % 40) / 39 * 2 - 1
            let v = Float(index / 40) / Float(count / 40) * 2 - 1
            let nose = max(0, 1 - 6 * (u * u + v * v)) * noseLength
            let z = 0.05 * (1 - 0.5 * (u * u + v * v)) + nose
            return SIMD3(u * width / 2, v * width * 0.65, z)
        }
    }
}

@Suite struct DepthSignatureTests {
    @Test func aFaceIsAtNoDistanceFromItself() throws {
        let face = try #require(DepthSignature(vertices: SyntheticMesh.vertices()))
        let again = try #require(DepthSignature(vertices: SyntheticMesh.vertices()))
        #expect(face.distance(to: again) == 0)
        #expect(face.points.count == 407 * 3)
    }

    @Test func aWiderFaceIsFartherAway() throws {
        let face = try #require(DepthSignature(vertices: SyntheticMesh.vertices(width: 0.14)))
        let wider = try #require(DepthSignature(vertices: SyntheticMesh.vertices(width: 0.15)))
        let apart = try #require(face.distance(to: wider))
        #expect(apart > 1)
    }

    /// An expression moves part of the mesh. The vertices that moved most are left out.
    @Test func aLocalChangeIsLeftOut() throws {
        var vertices = SyntheticMesh.vertices()
        // One kept vertex in five moves 2 cm.
        for index in vertices.indices where index % 15 == 0 {
            vertices[index].z += 0.02
        }
        let face = try #require(DepthSignature(vertices: SyntheticMesh.vertices()))
        let smiling = try #require(DepthSignature(vertices: vertices))
        let apart = try #require(face.distance(to: smiling))
        #expect(apart < 2)
    }

    @Test func meshesOfDifferentSizesDoNotCompare() throws {
        let face = try #require(DepthSignature(vertices: SyntheticMesh.vertices()))
        let other = try #require(DepthSignature(vertices: SyntheticMesh.vertices(count: 800)))
        #expect(face.distance(to: other) == nil)
    }
}

@Suite struct DepthIdentityScoreTests {
    private let kyle = UUID()
    private let anna = UUID()

    private func signature(width: Float) -> DepthSignature {
        DepthSignature(vertices: SyntheticMesh.vertices(width: width))!
    }

    @Test func scoresOwnAndNearestOther() throws {
        let templates = [
            kyle: [signature(width: 0.140), signature(width: 0.141)],
            anna: [signature(width: 0.150)],
        ]
        let score = DepthIdentityScore.score(signature(width: 0.1405), member: kyle, templates: templates)
        let own = try #require(score.own)
        let other = try #require(score.other)
        #expect(own < other)
        #expect(score.ownCount == 2)
        #expect(score.otherCount == 1)
        #expect(score.otherMember == anna)
    }

    /// A stranger is compared with everyone: how close a stranger comes is the evidence that matters most.
    @Test func aStrangerIsComparedWithEveryone() {
        let templates = [kyle: [signature(width: 0.140)], anna: [signature(width: 0.150)]]
        let score = DepthIdentityScore.score(signature(width: 0.148), member: nil, templates: templates)
        #expect(score.own == nil)
        #expect(score.otherMember == anna)
        #expect(score.otherCount == 2)
    }

    @Test func templatesAreKeptOnlyInLightAndSpreadOut() {
        let policy = DepthTemplatePolicy()
        let now = Date()
        #expect(policy.mayKeep(light: .dim, keptOnTrack: 0, lastKeptAt: nil, at: now))
        #expect(policy.mayKeep(light: .dark, keptOnTrack: 0, lastKeptAt: nil, at: now) == false)
        #expect(policy.mayKeep(light: nil, keptOnTrack: 0, lastKeptAt: nil, at: now) == false)
        #expect(policy.mayKeep(light: .normal, keptOnTrack: 3, lastKeptAt: nil, at: now) == false)
        #expect(policy.mayKeep(light: .normal, keptOnTrack: 1, lastKeptAt: now - 5, at: now) == false)
        #expect(policy.mayKeep(light: .normal, keptOnTrack: 1, lastKeptAt: now - 11, at: now))
    }

    /// The trace line carries distances, counts and names, nothing of the signature.
    @Test func theTraceLineHoldsOnlyScores() {
        var score = DepthIdentityScore()
        score.own = 1.4
        score.ownCount = 8
        score.other = 2.95
        score.otherCount = 6
        score.otherMember = anna
        let text = DepthIdentityEvaluator.describe(score, member: kyle, light: .dim, expression: 0.12, names: [kyle: "Kyle", anna: "Sam"])
        #expect(text == "depth identity Kyle, light dim, expression 0.12: own 1.40mm nearest of 8, others 2.95mm nearest of 6 (Sam)")
    }
}

/// Depth templates are stored like the face templates and go with the member.
@MainActor @Suite struct DepthTemplateStorageTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.depth.\(UUID())")!))
    private let kyle = HouseholdMember(name: "Kyle")

    private func temporaryStore() -> FaceTemplateStore {
        FaceTemplateStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-tests-\(UUID().uuidString)", isDirectory: true))
    }

    private func makeService(store: FaceTemplateStore) throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        services.household.add(kyle)
        let service = FaceRecognitionService(services: services, store: store)
        try service.saveEnrollment(memberID: kyle.id, embeddings: [LearningVectors.axis(0)])
        return service
    }

    private var signature: DepthSignature { DepthSignature(vertices: SyntheticMesh.vertices())! }

    /// In light, a confirmed member's signature is kept. A visit is scored only against other visits.
    @Test func keepsTemplatesInLightAndScoresOtherVisits() throws {
        let store = temporaryStore()
        let evaluator = DepthIdentityEvaluator(store: store)
        let first = UUID()
        let start = Date()
        evaluator.consider(signature, expression: 0.1, subject: .member(kyle.id), track: first, light: .normal, names: [:], at: start)
        #expect(evaluator.templates[kyle.id]?.templates.count == 1)
        evaluator.consider(signature, expression: 0.1, subject: .member(kyle.id), track: first, light: .normal, names: [:], at: start + 3)
        #expect(evaluator.templates[kyle.id]?.templates.count == 1)
        evaluator.consider(signature, expression: 0.1, subject: .member(kyle.id), track: UUID(), light: .dark, names: [:], at: start + 20)
        #expect(evaluator.templates[kyle.id]?.templates.count == 1)
        let reloaded = DepthIdentityEvaluator(store: store)
        try reloaded.load(enrolled: [kyle.id])
        #expect(reloaded.templates[kyle.id]?.templates.count == 1)
    }

    @Test func aStrangerNeverBecomesATemplate() {
        let evaluator = DepthIdentityEvaluator(store: temporaryStore())
        evaluator.consider(signature, expression: 0.1, subject: .stranger, track: UUID(), light: .bright, names: [:], at: Date())
        #expect(evaluator.hasTemplates == false)
    }

    @Test func deletingTheMembersFaceDataDeletesTheirDepthTemplates() throws {
        let store = temporaryStore()
        let service = try makeService(store: store)
        try store.saveDepth(MemberDepthTemplates(memberID: kyle.id, templates: [DepthTemplate(signature: signature, learnedAt: Date())]))
        service.load()
        #expect(service.depthIdentity.templates[kyle.id] != nil)
        service.deleteEnrollment(memberID: kyle.id)
        #expect(service.depthIdentity.templates[kyle.id] == nil)
        #expect(try store.loadDepth().isEmpty)
    }

    @Test func depthTemplatesMoveWithTheMember() throws {
        let store = temporaryStore()
        try store.saveDepth(MemberDepthTemplates(memberID: kyle.id, templates: [DepthTemplate(signature: signature, learnedAt: Date())]))
        let householdID = UUID()
        try store.move(from: kyle.id, to: householdID)
        let moved = try store.loadDepth()
        #expect(moved.map(\.memberID) == [householdID])
    }

    @Test func theDepthFolderIsLeftOutOfBackups() throws {
        let store = temporaryStore()
        try store.saveDepth(MemberDepthTemplates(memberID: kyle.id, templates: []))
        let values = try store.depthDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
