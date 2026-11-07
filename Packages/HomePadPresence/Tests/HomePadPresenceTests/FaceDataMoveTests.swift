import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// When this HomePad joins a household that already has a person, they take
/// the household's ID, and their face data on this iPad moves with them.
@MainActor @Suite struct FaceDataMoveTests {
    @Test func aPersonsFaceDataMovesToTheirNewIDOnThisIPad() throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.move.\(UUID())")!))
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        let store = FaceTemplateStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("move-tests-\(UUID().uuidString)", isDirectory: true))
        let kyle = HouseholdMember(name: "Kyle")
        services.household.add(kyle)
        let service = FaceRecognitionService(services: services, store: store)
        try service.saveEnrollment(memberID: kyle.id, embeddings: [LearningVectors.axis(0)])
        let sample = LearnedFaceSample(embedding: LearningVectors.axis(1), learnedAt: Date(), enrolledScore: 0.8, reliefMeters: 0.02)
        try store.saveLearned(LearnedFaceSamples(memberID: kyle.id, featurePrintRevision: FaceEmbedder.featurePrintRevision,
                                                 samples: [sample]))
        service.load()
        services.household.onMemberIDChange { old, new in service.moveMember(from: old, to: new) }

        let householdID = UUID()
        services.household.changeMemberID(from: kyle.id, to: householdID)
        #expect(service.hasEnrollment(householdID))
        #expect(!service.hasEnrollment(kyle.id))
        #expect(service.learnedCount(for: householdID) == 1)
        #expect(services.household.members.first?.hasFaceEnrollment == true)

        // On disk too, under the new ID only, so the next launch and the cleanup of removed people keep it.
        let reloaded = FaceRecognitionService(services: services, store: store)
        reloaded.load()
        reloaded.reconcile(with: services.household.members)
        #expect(reloaded.templates[householdID]?.memberID == householdID)
        #expect(reloaded.templates[kyle.id] == nil)
        #expect(reloaded.learnedCount(for: householdID) == 1)
    }
}
