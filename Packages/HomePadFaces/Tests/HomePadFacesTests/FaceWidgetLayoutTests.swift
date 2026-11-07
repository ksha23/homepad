import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Saving widget layouts, reflowing them into the other orientation, and
/// moving faces saved before the grid onto it.
@Suite struct FaceWidgetLayoutTests {
    private static let insets = Theme.Spacing.screenContent
    private static func cell(_ column: Int, _ row: Int) -> FaceGridCell { FaceGridCell(column: column, row: row) }

    // MARK: Storage

    @Test func layoutsSurviveARoundTrip() throws {
        let layout = FaceWidgetLayout(
            landscape: [FaceWidgetPlacement(widgetID: "a", size: .medium, cell: Self.cell(4, 0)),
                        FaceWidgetPlacement(widgetID: "b", size: .large)],
            portrait: nil
        )
        let face = FaceConfiguration(faceID: "faces.flow", widgetLayout: layout)
        let decoded = try JSONDecoder().decode(FaceConfiguration.self, from: JSONEncoder().encode(face))
        #expect(decoded == face)
        #expect(decoded.widgetLayout?.portrait == nil)
    }

    @Test func facesSavedBeforeTheGridDecodeWithNoLayout() throws {
        let json = #"{"id":"FACE0000-0000-4000-8000-000000000001","faceID":"faces.modular","values":{},"slots":{"widget1":"a"},"items":{}}"#
        let face = try JSONDecoder().decode(FaceConfiguration.self, from: Data(json.utf8))
        #expect(face.widgetLayout == nil)
        #expect(face.slots["widget1"] == "a")
    }

    // MARK: Widget settings

    /// A widget's settings serve both orientations, survive a round trip, and
    /// go with it when it is removed.
    @Test func widgetSettingsFollowTheWidget() throws {
        let list = WidgetSettingKey<String?>("list", default: nil)
        let tall = FaceWidgetPlacement(widgetID: "personal.reminders", size: .tall, cell: Self.cell(4, 0))
        let small = FaceWidgetPlacement(widgetID: "personal.reminders", size: .small, cell: Self.cell(4, 3))
        var layout = FaceWidgetLayout(landscape: [tall, small], portrait: [small, tall])
        var errands = WidgetSettings()
        errands[list] = "errands"
        layout.setSettings(errands, for: tall.id)
        #expect(layout.settings(for: tall.id)[list] == "errands")
        #expect(layout.settings(for: small.id).isEmpty)
        let face = FaceConfiguration(faceID: "faces.modular", widgetLayout: layout)
        let decoded = try JSONDecoder().decode(FaceConfiguration.self, from: JSONEncoder().encode(face))
        #expect(decoded.widgetLayout?.settings(for: tall.id)[list] == "errands")
        // Removed in landscape, it leaves portrait too, and its settings go.
        layout.save([small], for: .landscape)
        #expect(layout.portrait?.map(\.id) == [small.id])
        #expect(layout.widgetSettings == nil)
    }

    @Test func layoutsSavedBeforeWidgetSettingsDecode() throws {
        let json = #"{"landscape":[{"id":"FACE0000-0000-4000-8000-000000000002","widget":"a","size":"large"}]}"#
        let layout = try JSONDecoder().decode(FaceWidgetLayout.self, from: Data(json.utf8))
        #expect(layout.widgetSettings == nil)
        let placement = try #require(layout.landscape?.first)
        #expect(layout.settings(for: placement.id).isEmpty)
        let saved = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        #expect(!saved.contains("widgetSettings"))
    }

    /// Settings for a widget still in a face's old slots move the face onto the grid first.
    @Test func settingsOnAFaceSavedBeforeTheGridMoveItOntoTheGrid() {
        let list = WidgetSettingKey<String?>("list", default: nil)
        var face = FaceConfiguration(faceID: "faces.modular", slots: ["widget1": "personal.reminders"])
        let id = FaceWidgetMigration.placementID(face: face.id, slot: 0)
        var errands = WidgetSettings()
        errands[list] = "errands"
        face.setWidgetSettings(errands, for: id, legacySize: .medium)
        #expect(face.slots["widget1"] == nil)
        #expect(face.widgetLayout?.landscape?.first?.id == id)
        #expect(face.widgetSettings(for: id, legacySize: .medium)[list] == "errands")
    }

    @Test func aSizeFromALaterVersionReadsAsSmall() throws {
        let json = #"{"id":"FACE0000-0000-4000-8000-000000000009","widget":"a","size":"extraLarge","cell":{"column":1,"row":2}}"#
        let placement = try JSONDecoder().decode(FaceWidgetPlacement.self, from: Data(json.utf8))
        #expect(placement.size == .small)
        #expect(placement.cell == Self.cell(1, 2))
    }

    // MARK: Orientations

    @Test func anOrientationNobodyEditedReflowsTheOtherInReadingOrder() {
        let layout = FaceWidgetLayout(landscape: [
            FaceWidgetPlacement(widgetID: "bottom", size: .small, cell: Self.cell(0, 3)),
            FaceWidgetPlacement(widgetID: "unplaced", size: .small),
            FaceWidgetPlacement(widgetID: "top right", size: .small, cell: Self.cell(5, 0)),
            FaceWidgetPlacement(widgetID: "top left", size: .medium, cell: Self.cell(0, 0)),
        ])
        let portrait = layout.placements(for: .portrait)
        #expect(portrait.map(\.widgetID) == ["top left", "top right", "bottom", "unplaced"])
        #expect(portrait.allSatisfy { $0.cell == nil })
        // Its own arrangement once edited.
        #expect(layout.placements(for: .landscape) == layout.landscape)
    }

    @Test func reflowedWidgetsFillThePortraitGridInTheirOrder() {
        let landscape = [
            FaceWidgetPlacement(widgetID: "a", size: .medium, cell: Self.cell(4, 0)),
            FaceWidgetPlacement(widgetID: "b", size: .small, cell: Self.cell(0, 3)),
            FaceWidgetPlacement(widgetID: "c", size: .large, cell: Self.cell(2, 2)),
        ]
        let layout = FaceWidgetLayout(landscape: landscape)
        let grid = FaceGrid(size: CGSize(width: 834, height: 1210), insets: Self.insets)
        let board = FaceWidgetBoard(placements: layout.placements(for: .portrait), grid: grid, fill: .readingOrder)
        #expect(board.items.map(\.widgetID) == ["a", "c", "b"])
        #expect(board.items.map(\.area.origin) == [Self.cell(0, 0), Self.cell(2, 0), Self.cell(0, 1)])
        #expect(board.items.map(\.size) == [.medium, .large, .small])
    }

    @Test func savingOneOrientationAddsAndRemovesWidgetsInTheOther() {
        let kept = FaceWidgetPlacement(widgetID: "kept", size: .small, cell: Self.cell(0, 0))
        let removed = FaceWidgetPlacement(widgetID: "removed", size: .small, cell: Self.cell(1, 0))
        var layout = FaceWidgetLayout(landscape: [kept, removed], portrait: [kept, removed])
        let added = FaceWidgetPlacement(widgetID: "added", size: .medium, cell: Self.cell(2, 3))
        var moved = kept
        moved.cell = Self.cell(5, 3)
        layout.save([moved, added], for: .landscape)
        #expect(layout.landscape == [moved, added])
        // Portrait keeps its own cells, loses the removed widget and gains the new one with no cell.
        #expect(layout.portrait?.map(\.widgetID) == ["kept", "added"])
        #expect(layout.portrait?.first?.cell == Self.cell(0, 0))
        #expect(layout.portrait?.last?.cell == nil)
        #expect(layout.portrait?.last?.id == added.id)
    }

    @Test func savingWhenTheOtherOrientationWasNeverEditedLeavesItReflowing() {
        var layout = FaceWidgetLayout()
        layout.save([FaceWidgetPlacement(widgetID: "a", size: .small, cell: Self.cell(1, 1))], for: .portrait)
        #expect(layout.landscape == nil)
        #expect(layout.placements(for: .landscape).map(\.widgetID) == ["a"])
    }

    // MARK: Migration

    @Test func oldSlotsBecomePlacementsInSlotOrder() {
        let face = FaceConfiguration(faceID: "faces.modular",
                                     slots: ["widget10": "j", "widget2": "b", "widget1": "a", "widget3": "", "city1": "paris"])
        #expect(FaceWidgetMigration.legacyWidgetIDs(in: face) == ["a", "b", "j"])
        let layout = face.widgets(legacySize: .medium)
        #expect(layout.landscape?.map(\.widgetID) == ["a", "b", "j"])
        #expect(layout.landscape?.allSatisfy { $0.size == .medium && $0.cell == nil } == true)
        #expect(layout.portrait == nil)
        // The same IDs every time the face is read.
        #expect(face.widgets(legacySize: .medium) == layout)
        #expect(Set(layout.landscape?.map(\.id) ?? []).count == 3)
    }

    @Test func aFaceWithoutWidgetsHasAnEmptyLayout() {
        let face = FaceConfiguration(faceID: "faces.photos")
        #expect(face.widgets(legacySize: .small).isEmpty)
        var adopted = face
        adopted.adoptWidgetGrid(legacySize: .small)
        #expect(adopted.widgetLayout == nil)
    }

    @Test func adoptingTheGridMovesTheSlotsAndKeepsEverythingElse() {
        var face = FaceConfiguration(faceID: "faces.modular", values: ["style": "digital"],
                                     slots: ["widget1": "a", "widget2": "b", "camera": "front"])
        let read = face.widgets(legacySize: .medium)
        face.adoptWidgetGrid(legacySize: .medium)
        #expect(face.widgetLayout == read)
        #expect(face.slots == ["camera": "front"])
        #expect(face.values == ["style": "digital"])
        // A face already on the grid is left alone.
        var again = face
        again.slots["widget1"] = "stale"
        again.adoptWidgetGrid(legacySize: .medium)
        #expect(again.widgetLayout == read)
    }

    /// Kyle's iPads in both orientations.
    private static let screens = [
        CGSize(width: 1210, height: 834), CGSize(width: 834, height: 1210),
        CGSize(width: 1376, height: 1032), CGSize(width: 1032, height: 1376),
    ]

    @MainActor @Test func everyoneKeepsEveryWidgetTheyChoseOnModularAndPhotos() throws {
        for (faceID, count) in [("faces.modular", 4), ("faces.photos", 3)] {
            let definition = try #require(FaceCatalog.definition(faceID))
            let slots = Dictionary(uniqueKeysWithValues: (1...count).map { ("widget\($0)", "w\($0)") })
            let face = FaceConfiguration(faceID: faceID, slots: slots)
            let layout = face.widgets(legacySize: definition.widgets.legacySize)
            for screen in Self.screens {
                let grid = definition.widgets.grid(configuration: face, size: screen, insets: Self.insets)
                let board = FaceWidgetBoard(placements: layout.placements(for: grid.orientation), grid: grid,
                                            fill: definition.widgets.fill(for: grid.orientation))
                #expect(board.items.map(\.widgetID) == (1...count).map { "w\($0)" }, "\(faceID) \(screen)")
                #expect(board.leftOut.isEmpty, "\(faceID) \(screen)")
                // The profile button takes the top trailing cell, so on Modular's column one
                // widget can come out a size smaller there.
                let resized = board.items.filter { $0.size != definition.widgets.legacySize }
                #expect(resized.count <= 1, "\(faceID) \(screen)")
            }
        }
    }

    @MainActor @Test func modularWidgetsLandInAColumnBesideTheClockInLandscape() throws {
        let definition = try #require(FaceCatalog.definition("faces.modular"))
        let face = FaceConfiguration(faceID: "faces.modular", slots: ["widget1": "a", "widget2": "b"])
        let grid = definition.widgets.grid(configuration: face, size: CGSize(width: 1210, height: 834), insets: Self.insets)
        let board = FaceWidgetBoard(placements: face.widgets(legacySize: .medium).placements(for: .landscape),
                                    grid: grid, fill: definition.widgets.landscapeFill)
        #expect(board.items.map(\.area.column) == [4, 4])
    }

    @MainActor @Test func photosWidgetsLandInTheBottomRow() throws {
        let definition = try #require(FaceCatalog.definition("faces.photos"))
        let face = FaceConfiguration(faceID: "faces.photos", slots: ["widget1": "a", "widget2": "b", "widget3": "c"])
        for screen in Self.screens {
            let grid = definition.widgets.grid(configuration: face, size: screen, insets: Self.insets)
            let board = FaceWidgetBoard(placements: face.widgets(legacySize: .small).placements(for: grid.orientation),
                                        grid: grid, fill: definition.widgets.fill(for: grid.orientation))
            #expect(board.items.allSatisfy { $0.area.endRow == grid.rows }, "\(screen)")
        }
    }

    // MARK: Editor pages

    @MainActor @Test func everyFaceButSmartRotationEndsWithTheWidgetsPage() {
        for definition in FaceCatalog.all {
            let pages = definition.options(for: FaceConfiguration(faceID: definition.id))
            if definition.id == RotationEngine.selfID {
                #expect(pages.filter(\.isWidgetGrid).isEmpty)
            } else {
                #expect(pages.last?.isWidgetGrid == true, "\(definition.id)")
                #expect(pages.filter(\.isWidgetGrid).count == 1, "\(definition.id)")
            }
        }
    }
}
