import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import Testing
@testable import HomePadFaces

/// The faces HomePads share, what stays on one iPad, and how one face's
/// widgets land on each iPad size.
@MainActor @Suite struct FaceSharingTests {
    private func makeLibrary() -> (FaceLibrary, SettingsStore, Household) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "faces.sharing.\(UUID())")!)
        let household = Household(store: settings)
        return (FaceLibrary(settings: settings, household: household), settings, household)
    }

    private let photosID = UUID(uuidString: "0F0F0F0F-0000-4000-8000-000000000001")!

    @Test func sharedFacesLeaveThisIPadsPhotosOutAndKeepTheOtherIPadsOwn() throws {
        let (here, _, _) = makeLibrary()
        let (there, thereSettings, _) = makeLibrary()
        let weather = FaceWidgetPlacement(widgetID: "personal.weather", size: .medium, cell: FaceGridCell(column: 4, row: 0))
        here.save(FaceConfiguration(id: photosID, faceID: "faces.photos",
                                    values: ["source": "album", "albumID": "HERE-ALBUM", "albumTitle": "Trips", "style": "depth"],
                                    items: ["photos": ["HERE-1"]], widgetLayout: FaceWidgetLayout(landscape: [weather])),
                  for: .household)
        here.makeCurrent(photosID, for: .household)
        there.save(FaceConfiguration(id: photosID, faceID: "faces.photos", values: ["albumID": "THERE-ALBUM"],
                                     items: ["photos": ["THERE-1"]]),
                   for: .household)

        let shared = try #require(here.sharedList(for: .household))
        let sent = try #require(shared.faces.first { $0.id == photosID })
        #expect(sent.values == ["source": "album", "style": "depth"])
        #expect(sent.items.isEmpty)

        there.applyShared(try JSONValue(encoding: shared).decoded(as: SavedFaceList.self), for: .household)
        let landed = try #require(there.list(for: .household).faces.first { $0.id == photosID })
        #expect(landed.values["albumID"] == "THERE-ALBUM")
        #expect(landed.items["photos"] == ["THERE-1"])
        #expect(landed.values["style"] == "depth" && landed.values["source"] == "album")
        #expect(landed.widgetLayout?.landscape == [weather])
        // The current face shows there too.
        #expect(there.current(for: .household).id == photosID)
        #expect(thereSettings[CoreSettings.defaultFaceID] == "faces.photos")
        // Read back, it is what was shared, so it is never sent back as a change.
        #expect(there.sharedList(for: .household) == shared)
    }

    @Test func aPersonsFacesFollowTheirNewIDAndADeletionReturnsThemToTheHouseholds() {
        let (library, _, household) = makeLibrary()
        let kyle = HouseholdMember(name: "Kyle")
        household.add(kyle)
        #expect(library.sharedList(for: .member(kyle.id)) == nil)
        let numerals = library.add(faceID: "faces.numerals", to: .member(kyle.id))
        library.makeCurrent(numerals.id, for: .member(kyle.id))

        let householdID = UUID()
        library.moveOwner(from: kyle.id, to: householdID)
        #expect(library.hasOwnList(.member(householdID)))
        #expect(!library.hasOwnList(.member(kyle.id)))

        library.applyShared(nil, for: .member(kyle.id))
        #expect(household.members[0].preferences[HouseholdMember.facePreferenceKey] == nil)
        #expect(library.list(for: .member(kyle.id)) == library.list(for: .household))
    }

    @Test func smartRotationIsSharedAsSaved() throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "faces.rotation.\(UUID())")!)
        var rules = RotationSettings.defaults
        rules.fallbackFaceID = "faces.weather"
        settings[RotationStore.storageKey] = rules
        let content = try JSONValue(encoding: settings[RotationStore.storageKey])
        #expect(try content.decoded(as: RotationSettings.self) == rules)
    }

    // MARK: Screen sizes

    /// A face's size on the wall, with the burn-in margin, on each iPad in landscape.
    private static let walls = [CGSize(width: 1210, height: 834), CGSize(width: 1382, height: 1040), CGSize(width: 1392, height: 1048)]

    @Test func aFacesWidgetsKeepTheirCellsOnEveryIPad() {
        let placements = [FaceWidgetBoardTests.placement("personal.weather", .medium, FaceWidgetBoardTests.cell(4, 0)),
                          FaceWidgetBoardTests.placement("audio.nowplaying", .small, FaceWidgetBoardTests.cell(5, 3))]
        for wall in Self.walls {
            let grid = FaceWidgetBoardTests.grid(size: wall)
            let board = FaceWidgetBoard(placements: placements, grid: grid, fill: .readingOrder)
            #expect(grid.columns == 6 && grid.rows == 4)
            #expect(FaceWidgetBoardTests.origin(board, "personal.weather") == FaceWidgetBoardTests.cell(4, 0))
            #expect(FaceWidgetBoardTests.origin(board, "audio.nowplaying") == FaceWidgetBoardTests.cell(5, 3))
        }
        // Cells only grow with the screen.
        let cells = Self.walls.map { FaceWidgetBoardTests.grid(size: $0).cellSize.width }
        #expect(cells == cells.sorted())
    }

    @Test func aWidgetWhoseCellTheFaceNeedsHereWaitsElsewhereWithoutChangingTheSavedFace() {
        let placements = [FaceWidgetBoardTests.placement("personal.weather", .medium, FaceWidgetBoardTests.cell(4, 0))]
        let open = FaceWidgetBoard(placements: placements, grid: FaceWidgetBoardTests.grid(size: Self.walls[2]), fill: .readingOrder)
        let blocked = FaceWidgetBoard(placements: placements, grid: FaceWidgetBoardTests.grid(clock: true, size: Self.walls[0]),
                                      fill: .readingOrder)
        #expect(FaceWidgetBoardTests.origin(open, "personal.weather") == FaceWidgetBoardTests.cell(4, 0))
        let moved = FaceWidgetBoardTests.origin(blocked, "personal.weather")
        #expect(moved != nil && moved != FaceWidgetBoardTests.cell(4, 0))
        #expect(FaceWidgetBoardTests.isValid(blocked))
        #expect(placements[0].cell == FaceWidgetBoardTests.cell(4, 0))
    }
}
