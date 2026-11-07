import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

/// A face set up on another HomePad names that HomePad's HomeKit IDs. The
/// Home and Cameras faces and the editor read them as this HomePad knows them.
@MainActor @Suite struct SavedHomeIDsTests {
    /// A home where the kitchen HomePad's IDs are `hk:kitchen-<this HomePad's ID>`.
    @MainActor
    private final class TranslatingHome: SmartHomeService {
        var accessories: [HomeAccessory] = []
        var scenes: [HomeScene] = []
        var cameras: [HomeCamera] = []
        var connectedBackends: Set<SmartHomeBackend> = []
        var favoriteAccessoryIDs: [HomeAccessory.ID] = []

        func localID(for id: String) -> String {
            id.hasPrefix("hk:kitchen-") ? String(id.dropFirst("hk:kitchen-".count)) : id
        }

        func refresh() async {}
        func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {}
        func activateScene(_ sceneID: HomeScene.ID) async throws {}
        func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }
        func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {}
    }

    private func camera(_ id: String) -> HomeCamera {
        HomeCamera(id: id, name: id.capitalized, backend: .homeKit)
    }

    @Test func tileIDsReadAsThisHomePadKnowsThem() {
        let home = TranslatingHome()
        #expect(HomeTile.localID("accessory:hk:kitchen-hk:lamp", in: home) == "accessory:hk:lamp")
        #expect(HomeTile.localID("scene:hk:kitchen-hk:night", in: home) == "scene:hk:night")
        #expect(HomeTile.localID("accessory:hk:lamp", in: home) == "accessory:hk:lamp")
        #expect(HomeTile.localID("intercom", in: home) == "intercom")
        #expect(SlotItem.localID("hk:kitchen-hk:porch", gallery: .cameras, home: home) == "hk:porch")
        #expect(SlotItem.localID("london", gallery: .cities, home: home) == "london")
    }

    @Test func camerasPickedOnTheOtherHomePadShowHereOnce() {
        let home = TranslatingHome()
        let available = [camera("hk:porch"), camera("hk:garden")]
        let configuration = FaceConfiguration(faceID: "faces.cameras", slots: [
            "camera1": "hk:kitchen-hk:garden", "camera2": "hk:garden", "camera3": "hk:kitchen-hk:porch",
        ])
        let shown = CamerasFace.chosenCameras(configuration, available: available) { home.localID(for: $0) }
        #expect(shown.map(\.id) == ["hk:garden", "hk:porch"])
    }
}
