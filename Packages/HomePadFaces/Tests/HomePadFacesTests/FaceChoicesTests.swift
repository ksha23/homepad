import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

/// What the new face choices resolve to: empty means automatic, slot order is
/// kept, and things that no longer exist are skipped.
@MainActor @Suite struct FaceChoicesTests {
    private func accessory(_ id: String, _ name: String, room: String? = nil, kind: AccessoryKind = .light,
                           groupID: String? = nil) -> HomeAccessory {
        HomeAccessory(id: id, name: name, room: room, kind: kind, backend: .demo, groupID: groupID)
    }

    private func camera(_ id: String) -> HomeCamera {
        HomeCamera(id: id, name: id.capitalized, backend: .demo)
    }

    // MARK: Home face

    private let lamp = HomeAccessory(id: "lamp", name: "Lamp", room: "Living Room", kind: .light, backend: .demo)
    private let thermostat = HomeAccessory(id: "heat", name: "Thermostat", room: "Hall", kind: .thermostat, backend: .demo)
    private let lock = HomeAccessory(id: "lock", name: "Front Door", room: "Hall", kind: .lock, backend: .demo)
    private let evening = HomeScene(id: "evening", name: "Evening", backend: .demo)

    @Test func emptyTilesShowTheFavoritesAsBefore() {
        let tiles = HomeTile.tiles(favorites: [lamp, thermostat], cameras: [camera("porch")], scenes: [evening],
                                   includesClockAndCamera: true, accessories: [lamp, thermostat, lock], chosen: [])
        #expect(tiles.map(\.id) == ["clock", "accessory:heat", "intercom", "camera:porch", "accessory:lamp", "scene:evening", "home"])
    }

    @Test func chosenTilesKeepSlotOrderAndSkipWhatIsGone() {
        let tiles = HomeTile.tiles(favorites: [lamp], cameras: [], scenes: [evening], includesClockAndCamera: false,
                                   accessories: [lamp, lock],
                                   chosen: ["scene:evening", "accessory:removed", "accessory:lock", "accessory:lock"])
        #expect(tiles.map(\.id) == ["intercom", "scene:evening", "accessory:lock", "home"])
    }

    @Test func tilesThatAreAllGoneFallBackToTheFavorites() {
        let tiles = HomeTile.tiles(favorites: [lamp], cameras: [], scenes: [], includesClockAndCamera: false,
                                   accessories: [lamp], chosen: ["accessory:removed"])
        #expect(tiles.map(\.id) == ["intercom", "accessory:lamp", "home"])
    }

    @Test func theChosenCameraShowsOrTheFirstWhenItIsGone() {
        let cameras = [camera("porch"), camera("garden")]
        #expect(HomeTile.camera("garden", in: cameras)?.id == "garden")
        #expect(HomeTile.camera(nil, in: cameras)?.id == "porch")
        #expect(HomeTile.camera("removed", in: cameras)?.id == "porch")
        #expect(HomeTile.camera(nil, in: []) == nil)
        let tiles = HomeTile.tiles(favorites: [], cameras: cameras, scenes: [], includesClockAndCamera: true, camera: "garden")
        #expect(tiles.contains { $0.id == "camera:garden" })
    }

    @Test func theGalleryListsAccessoriesByRoomThenScenes() {
        let items = SlotItem.homeItems(
            accessories: [
                accessory("b", "Lamp", room: "Kitchen"), accessory("a", "Lamp", room: "Bedroom"),
                accessory("loose", "Plug", kind: .switchOutlet), accessory("cam", "Porch", room: "Porch", kind: .camera),
                accessory("member", "Bulb", room: "Kitchen", groupID: "group"),
            ],
            scenes: [evening]
        )
        #expect(items.map(\.id) == ["accessory:a", "accessory:b", "accessory:loose", "scene:evening"])
        #expect(items.map(\.subtitle) == ["Bedroom", "Kitchen", nil, "Scene"])
        let sections = SlotItem.sections(items, matching: "")
        #expect(sections.map(\.title) == ["Bedroom", "Kitchen", "Other", "Scenes"])
        // Searching a room finds what is in it, so two Lamps can be told apart.
        #expect(SlotItem.sections(items, matching: "kitchen").flatMap(\.items).map(\.id) == ["accessory:b"])
    }

    // MARK: Cameras face

    @Test func emptyCameraSlotsShowTheFirstNine() {
        let available = (1...12).map { camera("cam\($0)") }
        let shown = CamerasFace.chosenCameras(FaceConfiguration(faceID: "faces.cameras"), available: available)
        #expect(shown.map(\.id) == (1...9).map { "cam\($0)" })
    }

    @Test func chosenCamerasKeepSlotOrderAndSkipWhatIsGone() {
        let available = [camera("porch"), camera("garden"), camera("garage")]
        let configuration = FaceConfiguration(faceID: "faces.cameras", slots: [
            "camera1": "garage", "camera2": "", "camera3": "removed", "camera4": "porch", "camera5": "garage",
        ])
        #expect(CamerasFace.chosenCameras(configuration, available: available).map(\.id) == ["garage", "porch"])
        let gone = FaceConfiguration(faceID: "faces.cameras", slots: ["camera1": "removed"])
        #expect(CamerasFace.chosenCameras(gone, available: available).map(\.id) == ["porch", "garden", "garage"])
    }

    @Test func aDoorbellThatRangMovesToTheFront() {
        let cameras = [camera("garden"), camera("porch")]
        #expect(CamerasFace.ordered(cameras, ringing: "porch").map(\.id) == ["porch", "garden"])
        #expect(CamerasFace.ordered(cameras, ringing: "removed").map(\.id) == ["garden", "porch"])
        #expect(CamerasFace.ordered(cameras, ringing: nil).map(\.id) == ["garden", "porch"])
    }

    // MARK: Modular, Weather, Calendar, Photos

    @Test func modularShowsEventsAndForecastUntilSomethingElseIsChosen() {
        let saved = FaceConfiguration(faceID: "faces.modular")
        #expect(saved.value(ModularFace.details) == ModularLowerRow.Content.eventsAndForecast.rawValue)
        let events = FaceConfiguration(faceID: "faces.modular", values: ["details": "events"])
        #expect(ModularLowerRow.Content(rawValue: events.value(ModularFace.details)) == .events)
        let unknown = FaceConfiguration(faceID: "faces.modular", values: ["details": "gone"])
        #expect(unknown.value(ModularFace.details) == "both")
    }

    @Test func everyCityCanAskForItsWeather() {
        for city in WorldCity.all {
            #expect((-90...90).contains(city.latitude), "\(city.id)")
            #expect((-180...180).contains(city.longitude), "\(city.id)")
            #expect(city.latitude != 0 || city.longitude != 0, "\(city.id)")
            #expect(city.weatherLocation.name == city.name)
            #expect(city.weatherLocation.timeZoneID == city.timeZoneID)
        }
        #expect(WorldCity.city("london")?.weatherLocation.latitude == 51.51)
    }

    @Test func weatherShowsTheCurrentLocationUntilACityIsChosen() async {
        let saved = FaceConfiguration(faceID: "faces.weather")
        #expect(saved.slot("place") == nil)
        let service = DemoWeatherService()
        let tokyo = WorldCity.city("tokyo")!
        let snapshot = await service.snapshot(for: tokyo.weatherLocation)
        #expect(snapshot?.locationName == "Tokyo")
    }

    @Test func calendarKeepsTheMonthUntilUpNextIsChosen() {
        #expect(FaceConfiguration(faceID: "faces.calendar").value(CalendarFace.style) == "month")
    }

    @Test func savedPhotoSourcesStillLoad() {
        // Saved names never change. New sources are added at the end.
        #expect(PhotoSourceKind.allCases.map(\.rawValue) == ["featured", "library", "favorites", "portraits", "album", "picked", "single"])
    }

    @Test func newOptionsUseKeysOfTheirOwn() {
        // A new option must not reuse a key an existing option of the face stores.
        // The widgets page every face ends with has a key of its own too.
        for definition in FaceCatalog.all {
            let ids = definition.options(for: FaceConfiguration(faceID: definition.id)).map(\.id)
            #expect(Set(ids).count == ids.count, "\(definition.id)")
        }
        #expect(HomeModularFace.definition.options.map(\.id) == ["style", "color", "tiles", "camera"])
        #expect(CamerasFace.definition.options.map(\.id) == ["style", "cameras"])
        #expect(WeatherFace.definition.options.map(\.id) == ["style", "place"])
        #expect(ModularFace.definition.options.map(\.id) == ["style", "color", "details"])
        #expect(PhotosFace.definition.options.map(\.id) == ["source", "style", "tint", "interval"])
    }
}
