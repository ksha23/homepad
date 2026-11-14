import Foundation
import HomePadCore
import simd
import Testing
@testable import HomePadPresence

/// A synthetic face as the depth map shows it: a curved head with a nose,
/// sized by `width`, its surface within 9 cm of the nose tip on a grid.
enum SyntheticDepthFace {
    /// How far behind the nose tip the face is at (x, y), in meters.
    static func depth(x: Float, y: Float, width: Float, noseLength: Float) -> Float {
        let curve = 0.05 * ((x / (width / 2)) * (x / (width / 2)) + (y / (width * 0.65)) * (y / (width * 0.65)))
        let nose = noseLength * (1 - exp(-(x * x + y * y) / (0.015 * 0.015)))
        return curve + nose
    }

    /// Signature points, turned by `turnDegrees` about the vertical axis
    /// through the nose tip and moved by `shift`.
    static func points(
        width: Float = 0.14, noseLength: Float = 0.03, turnDegrees: Float = 0, shift: SIMD3<Float> = .zero
    ) -> [Float] {
        let angle = turnDegrees * .pi / 180
        var points: [Float] = []
        for y in stride(from: Float(-0.09), through: 0.09, by: 0.0036) {
            for x in stride(from: Float(-0.09), through: 0.09, by: 0.0036) {
                let z = depth(x: x, y: y, width: width, noseLength: noseLength)
                let p = SIMD3<Float>(x, y, z)
                guard simd_length(p) <= 0.09 else { continue }
                let turned = SIMD3<Float>(p.x * cos(angle) + p.z * sin(angle), p.y, -p.x * sin(angle) + p.z * cos(angle)) + shift
                points.append(contentsOf: [turned.x, turned.y, turned.z])
            }
        }
        return points
    }

    static func signature(width: Float = 0.14, noseLength: Float = 0.03, turnDegrees: Float = 0) -> DepthSignature {
        DepthSignature(points: points(width: width, noseLength: noseLength, turnDegrees: turnDegrees))
    }
}

@Suite struct DepthSignatureTests {
    @Test func aFaceIsAtNoDistanceFromItself() throws {
        let face = SyntheticDepthFace.signature()
        let apart = try #require(face.distance(to: SyntheticDepthFace.signature()))
        // What is left is the surface grid's own error on a curved face.
        #expect(apart < 0.3)
    }

    /// Where the head is and a small turn of it do not matter: the faces are lined up first.
    @Test func aTurnedAndMovedFaceIsStillClose() throws {
        let face = SyntheticDepthFace.signature()
        let turned = DepthSignature(points: SyntheticDepthFace.points(turnDegrees: 10, shift: SIMD3(0.003, -0.002, 0.004)))
        let apart = try #require(turned.distance(to: face))
        #expect(apart < 0.5)
    }

    @Test func anotherFaceIsFartherAway() throws {
        let face = SyntheticDepthFace.signature()
        let other = SyntheticDepthFace.signature(width: 0.155, noseLength: 0.022)
        let apart = try #require(other.distance(to: face))
        let same = try #require(SyntheticDepthFace.signature(turnDegrees: 8).distance(to: face))
        #expect(apart > same * 3)
    }

    @Test func aFaceTurnedFarAwayDoesNotCompare() {
        let face = SyntheticDepthFace.signature()
        #expect(SyntheticDepthFace.signature(turnDegrees: 60).distance(to: face) == nil)
    }

    /// Templates from ARKit's face mesh, which had no version, no longer load.
    @Test func meshSignaturesNoLongerLoad() throws {
        let old = Data(#"{"points":[0,0,0]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DepthSignature.self, from: old) }
        let current = try JSONEncoder().encode(SyntheticDepthFace.signature())
        #expect(try JSONDecoder().decode(DepthSignature.self, from: current) == SyntheticDepthFace.signature())
    }
}

/// Finding the face on the followed head in a depth map, with no image and no ARKit.
@Suite struct DepthFaceFinderTests {
    private let width = 320
    private let height = 240
    private let focal = 300.0

    /// A wall at 2 m with `surface` in front of it around the map's center, `distance` away at its nearest.
    private func map(distance: Float, surface: (Float, Float) -> Float?) -> DepthMap {
        var meters = [Float](repeating: 2, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                // Solve for the depth along this pixel's ray, with the surface's own depth at its x and y.
                var z = distance
                for _ in 0..<4 {
                    let x = (Float(column) - Float(width) / 2) * z / Float(focal)
                    let y = (Float(row) - Float(height) / 2) * z / Float(focal)
                    guard let behind = surface(x, y) else { z = .nan; break }
                    z = distance + behind
                }
                if z.isFinite { meters[row * width + column] = z }
            }
        }
        return DepthMap(width: width, height: height, meters: meters, focalLength: focal)
    }

    private func head(at distance: Double) -> DepthPersonTracker.Person {
        let radius = 0.12 * focal / distance
        return DepthPersonTracker.Person(
            id: UUID(), center: CGPoint(x: 0.5, y: 0.5), distanceMeters: distance,
            radius: CGSize(width: radius / Double(width), height: radius / Double(height)),
            confirmedAt: 0, confirmedCenter: CGPoint(x: 0.5, y: 0.5), confirmedDistance: distance, seenAt: 0
        )
    }

    @Test func findsTheNoseTipAndTheFaceAroundIt() throws {
        let depthMap = map(distance: 0.5) { x, y in
            x * x + y * y <= 0.11 * 0.11 ? SyntheticDepthFace.depth(x: x, y: y, width: 0.14, noseLength: 0.03) : nil
        }
        let face = try #require(DepthFaceFinder.find(in: depthMap, head: head(at: 0.52), orientation: .up))
        #expect(abs(face.nosePoint.x - 0.5) < 0.02)
        #expect(abs(face.nosePoint.y - 0.5) < 0.02)
        #expect(abs(face.noseMeters - 0.5) < 0.01)
        #expect(face.pointCount >= DepthFaceFinder.minimumPoints)
        #expect(DepthFaceFinder.reliefRange.contains(face.relief))
    }

    /// A photo is flat: nothing falls away behind its nearest point.
    @Test func aFlatPictureIsNoFace() {
        let photo = map(distance: 0.5) { x, y in x * x + y * y <= 0.11 * 0.11 ? 0 : nil }
        #expect(DepthFaceFinder.find(in: photo, head: head(at: 0.5), orientation: .up) == nil)
    }

    /// The same face, found by depth, compares as the same face.
    @Test func aFoundFaceMatchesItsSyntheticSignature() throws {
        let depthMap = map(distance: 0.5) { x, y in
            x * x + y * y <= 0.11 * 0.11 ? SyntheticDepthFace.depth(x: x, y: y, width: 0.14, noseLength: 0.03) : nil
        }
        let face = try #require(DepthFaceFinder.find(in: depthMap, head: head(at: 0.52), orientation: .up))
        let same = try #require(DepthSignature(face: face).distance(to: SyntheticDepthFace.signature()))
        let other = try #require(DepthSignature(face: face).distance(to: SyntheticDepthFace.signature(width: 0.155, noseLength: 0.022)))
        #expect(same < other)
    }
}

@Suite struct DepthIdentityScoreTests {
    private let kyle = UUID()
    private let anna = UUID()

    private func signature(width: Float) -> DepthSignature {
        SyntheticDepthFace.signature(width: width)
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

    private var signature: DepthSignature { SyntheticDepthFace.signature() }

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
