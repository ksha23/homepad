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

    /// Templates from ARKit's face mesh (no version) and from single depth maps (version 2) no longer load.
    @Test func olderSignaturesNoLongerLoad() throws {
        let mesh = Data(#"{"points":[0,0,0]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DepthSignature.self, from: mesh) }
        let single = Data(#"{"version":2,"points":[0,0,0]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DepthSignature.self, from: single) }
        let current = try JSONEncoder().encode(SyntheticDepthFace.signature())
        #expect(try JSONDecoder().decode(DepthSignature.self, from: current) == SyntheticDepthFace.signature())
    }
}

/// Finding the face in a face box of a depth map, with no image and no ARKit.
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

    /// A face box around the map's center, as `DepthFaceDetector` gives it,
    /// for a face about 16 cm across at `distance`.
    private func faceBox(at distance: Double) -> CGRect {
        let half = 0.08 * focal / distance
        let width = 2 * half / Double(self.width)
        let height = 2 * half / Double(self.height)
        return CGRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height)
    }

    private func find(in map: DepthMap, distance: Double) -> DepthFace? {
        DepthFaceFinder.search(in: map, faceBox: faceBox(at: distance), orientation: .up).face
    }

    @Test func findsTheNoseTipAndTheFaceAroundIt() throws {
        let depthMap = map(distance: 0.5) { x, y in
            x * x + y * y <= 0.11 * 0.11 ? SyntheticDepthFace.depth(x: x, y: y, width: 0.14, noseLength: 0.03) : nil
        }
        let face = try #require(find(in: depthMap, distance: 0.5))
        #expect(abs(face.nosePoint.x - 0.5) < 0.02)
        #expect(abs(face.nosePoint.y - 0.5) < 0.02)
        #expect(abs(face.noseMeters - 0.5) < 0.01)
        #expect(face.pointCount >= DepthFaceFinder.minimumPoints)
        #expect(DepthFaceFinder.reliefRange.contains(face.relief))
    }

    /// A photo is flat: nothing falls away behind its nearest point.
    @Test func aFlatPictureIsNoFace() {
        let photo = map(distance: 0.5) { x, y in x * x + y * y <= 0.11 * 0.11 ? 0 : nil }
        #expect(find(in: photo, distance: 0.5) == nil)
    }

    /// The same face, found by depth, compares as the same face.
    @Test func aFoundFaceMatchesItsSyntheticSignature() throws {
        let depthMap = map(distance: 0.5) { x, y in
            x * x + y * y <= 0.11 * 0.11 ? SyntheticDepthFace.depth(x: x, y: y, width: 0.14, noseLength: 0.03) : nil
        }
        let face = try #require(find(in: depthMap, distance: 0.5))
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

/// A synthetic face with depth noise, as one depth map would give it.
private func noisyFace(seed: UInt64, noise: Float = 0.0015, shift: SIMD3<Float> = .zero) -> DepthFace {
    var state = seed
    func random() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24) * 2 - 1
    }
    var points = SyntheticDepthFace.points(shift: shift)
    for index in stride(from: 2, to: points.count, by: 3) { points[index] += random() * noise }
    return DepthFace(nosePoint: .zero, noseMeters: 0.5, points: points, relief: 0.03, coverage: 0.9)
}

@Suite struct DepthFaceFusionTests {
    /// Merging a handful of noisy depth maps of a still face brings it closer to the face than any one of them.
    @Test func mergingLowersTheNoise() throws {
        let faces = (0..<5).map { noisyFace(seed: UInt64($0 + 1), shift: SIMD3(Float($0) * 0.001, 0, 0)) }
        let merged = try #require(DepthFaceFusion.fuse(faces))
        let clean = SyntheticDepthFace.signature()
        let single = try #require(DepthSignature(points: faces[0].points).distance(to: clean))
        let fused = try #require(DepthSignature(points: merged).distance(to: clean))
        #expect(fused < single)
    }

    @Test func tooFewFacesDoNotMerge() {
        #expect(DepthFaceFusion.fuse([noisyFace(seed: 1), noisyFace(seed: 2)]) == nil)
    }
}

@Suite struct DepthCalibrationTests {
    private let policy = DepthTemplatePolicy()

    private func templates(visits: Int, perVisit: Int) -> [DepthTemplate] {
        let start = Date()
        return (0..<visits).flatMap { visit in
            (0..<perVisit).map { index in
                let face = noisyFace(seed: UInt64(visit * 10 + index + 1))
                return DepthTemplate(
                    signature: DepthSignature(points: face.points),
                    learnedAt: start + Double(visit) * 3600 + Double(index) * 10
                )
            }
        }
    }

    @Test func aLimitComesFromOtherVisits() throws {
        let calibration = DepthCalibration.calibrate(templates(visits: 2, perVisit: 3), policy: policy)
        #expect(calibration.visits == 2)
        let limit = try #require(calibration.threshold)
        #expect(limit > 0)
        // Another face is beyond it.
        let other = SyntheticDepthFace.signature(width: 0.155, noseLength: 0.022)
        let apart = try #require(other.distance(to: DepthSignature(points: noisyFace(seed: 1).points)))
        #expect(apart > limit)
    }

    /// One sitting gives a limit too: twice the largest distance among its templates, at least 1 mm.
    @Test func oneSittingUsesItsOwnSpread() throws {
        let calibration = DepthCalibration.calibrate(templates(visits: 1, perVisit: 3), policy: policy)
        let limit = try #require(calibration.threshold)
        #expect(limit >= policy.oneSittingFloor)
        #expect(limit <= policy.maximumThreshold)
    }

    @Test func tooFewTemplatesGiveNoLimit() {
        let calibration = DepthCalibration.calibrate(templates(visits: 1, perVisit: 2), policy: policy)
        #expect(calibration.threshold == nil)
        #expect(calibration.describe(policy: policy) == "2 templates from 1 visit, needs 3")
    }
}

/// Depth names a member on enough votes under their limit, clearly nearer them than anyone else, unless the camera called the face a stranger.
@MainActor @Suite struct DepthDecisionTests {
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.depthdecision.\(UUID())")!))
    private let kyle = HouseholdMember(name: "Kyle")
    private let sam = HouseholdMember(name: "Sam")
    private let person = UUID()
    private let t0 = Date()

    private func makeService() throws -> FaceRecognitionService {
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        services.household.add(kyle)
        services.household.add(sam)
        let service = FaceRecognitionService(services: services, store: nil)
        try service.saveEnrollment(memberID: kyle.id, embeddings: [LearningVectors.axis(0)])
        try service.saveEnrollment(memberID: sam.id, embeddings: [LearningVectors.axis(1)])
        service.updateSensing(isWatching: true, isSomeonePresent: true, at: t0)
        service.depthIdentity.use(DepthCalibration(templates: 8, visits: 2, threshold: 1.5), for: kyle.id)
        // The depth face on the followed person is the face in view.
        service.noteFaces(count: 1, track: person, at: t0)
        return service
    }

    private func score(_ distance: Double, runnerUp: Double? = nil) -> DepthIdentityScore {
        var score = DepthIdentityScore()
        score.other = distance
        score.otherMember = kyle.id
        score.runnerUp = runnerUp
        return score
    }

    @Test func threeVotesUnderTheLimitNameThemInTheDark() throws {
        let service = try makeService()
        for index in 0..<2 { service.noteDepthScore(score(1.0), look: service.currentLook, light: .dark, at: t0 + Double(index)) }
        #expect(services.household.session.mode == .guest)
        service.noteDepthScore(score(1.1), look: service.currentLook, light: .dark, at: t0 + 2)
        #expect(services.household.session.mode == .recognized(kyle.id))
        #expect(service.confirmedByDepth)
    }

    /// The camera and depth decide together: in dim light the camera tried and was never sure.
    @Test func depthDecidesInLightToo() throws {
        let service = try makeService()
        for index in 0..<3 { service.noteDepthScore(score(1.0), look: service.currentLook, light: .normal, at: t0 + Double(index)) }
        #expect(services.household.session.mode == .recognized(kyle.id))
    }

    @Test func aCameraStrangerStopsDepth() throws {
        let service = try makeService()
        for index in 0..<4 {
            let sample = LearningVectors.sample(LearningVectors.axis(5 + index), track: person)
            service.consider(sample, requireLiveness: true, at: t0 + Double(index) * 0.2)
        }
        for index in 0..<3 { service.noteDepthScore(score(1.0), look: service.currentLook, light: .normal, at: t0 + 2 + Double(index)) }
        #expect(services.household.session.mode == .guest)
    }

    /// In dim light the camera's matches of a member fall, so its "stranger" holds depth back no longer.
    @Test func aCameraStrangerInDimLightDoesNotStopDepth() throws {
        let service = try makeService()
        for index in 0..<4 {
            let sample = LearningVectors.sample(LearningVectors.axis(5 + index), track: person)
            service.consider(sample, requireLiveness: true, light: .dim, at: t0 + Double(index) * 0.2)
        }
        for index in 0..<3 { service.noteDepthScore(score(1.0), look: service.currentLook, light: .dim, at: t0 + 2 + Double(index)) }
        #expect(services.household.session.mode == .recognized(kyle.id))
    }

    @Test func overTheLimitOrTooCloseToSomeoneElseIsNoVote() throws {
        let service = try makeService()
        for index in 0..<2 { service.noteDepthScore(score(2.0), look: service.currentLook, light: .dark, at: t0 + Double(index)) }
        for index in 2..<4 { service.noteDepthScore(score(1.0, runnerUp: 1.1), look: service.currentLook, light: .dark, at: t0 + Double(index)) }
        #expect(services.household.session.mode == .guest)
        #expect(service.depthVotes.allSatisfy { $0 == nil })
    }

    /// A score worked out for a face that has since left counts for nothing.
    @Test func aScoreForAnotherLookIsIgnored() throws {
        let service = try makeService()
        for index in 0..<3 { service.noteDepthScore(score(1.0), look: UUID(), light: .dark, at: t0 + Double(index)) }
        #expect(services.household.session.mode == .guest)
        #expect(service.depthVotes.isEmpty)
    }
}

/// Depth's votes in the dark: under the limit, clearly nearer one member than any other.
@Suite struct DepthVoterTests {
    private let kyle = UUID()
    private let sam = UUID()

    private func score(_ best: Double, runnerUp: Double? = nil) -> DepthIdentityScore {
        var score = DepthIdentityScore()
        score.other = best
        score.otherMember = kyle
        score.runnerUp = runnerUp
        return score
    }

    @Test func threeOfFourNameTheMember() {
        var voter = DepthVoter(policy: DepthTemplatePolicy())
        let limits = [kyle: 1.5]
        #expect(voter.vote(on: score(2.0), limits: limits, name: { _ in "Kyle" }).winner == nil)
        #expect(voter.vote(on: score(1.0), limits: limits, name: { _ in "Kyle" }).winner == nil)
        #expect(voter.vote(on: score(1.2), limits: limits, name: { _ in "Kyle" }).winner == nil)
        let outcome = voter.vote(on: score(0.9), limits: limits, name: { _ in "Kyle" })
        #expect(outcome.winner == kyle)
        #expect(outcome.reason == "Kyle 0.90 mm, under the 1.50 mm limit")
        #expect(voter.describe(name: { _ in "Kyle" }) == "- K K K, 3 of 4 needed")
    }

    @Test func noLimitOrTooCloseToSomeoneElseIsNoVote() {
        var voter = DepthVoter(policy: DepthTemplatePolicy())
        #expect(voter.vote(on: score(1.0), limits: [:], name: { _ in "Kyle" }).reason == "Kyle 1.00 mm, no limit yet")
        let close = voter.vote(on: score(1.0, runnerUp: 1.1), limits: [kyle: 1.5], name: { _ in "Kyle" })
        #expect(close.vote == nil)
        #expect(close.reason == "Kyle 1.00 mm, too close to someone else")
    }
}
