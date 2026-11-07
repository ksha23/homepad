import CoreGraphics
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// The grid widgets snap to on a face: its cells on every iPad, and the
/// cells a face's own content blocks.
@Suite struct FaceGridTests {
    /// Kyle's iPads and the simulators, landscape then portrait.
    static let screens = [
        CGSize(width: 1210, height: 834), CGSize(width: 834, height: 1210),
        CGSize(width: 1376, height: 1032), CGSize(width: 1032, height: 1376),
        CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
        CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
    ]
    static let insets = Theme.Spacing.screenContent

    @Test func landscapeIsSixByFourAndPortraitFourBySix() {
        for screen in Self.screens {
            let grid = FaceGrid(size: screen, insets: Self.insets)
            let isLandscape = screen.width > screen.height
            #expect(grid.orientation == (isLandscape ? .landscape : .portrait), "\(screen)")
            #expect(grid.columns == (isLandscape ? 6 : 4), "\(screen)")
            #expect(grid.rows == (isLandscape ? 4 : 6), "\(screen)")
        }
    }

    @Test func cellsFillTheContentAreaAndComeOutNearlySquare() {
        for screen in Self.screens {
            let grid = FaceGrid(size: screen, insets: Self.insets)
            let all = grid.frame(for: FaceGridArea(column: 0, row: 0, columns: grid.columns, rows: grid.rows))
            #expect(abs(all.minX - Self.insets.leading) < 0.5, "\(screen)")
            #expect(abs(all.maxX - (screen.width - Self.insets.trailing)) < 0.5, "\(screen)")
            #expect(abs(all.minY - Self.insets.top) < 0.5, "\(screen)")
            #expect(abs(all.maxY - (screen.height - Self.insets.bottom)) < 0.5, "\(screen)")
            let aspect = grid.cellSize.width / grid.cellSize.height
            #expect(aspect > 0.8 && aspect < 1.2, "\(screen) cell \(grid.cellSize)")
            // At least the size of a small widget on the Home Screen.
            #expect(min(grid.cellSize.width, grid.cellSize.height) > 150, "\(screen) cell \(grid.cellSize)")
        }
    }

    @Test func areasSpanTheGapsBetweenTheirCells() {
        let grid = FaceGrid(size: CGSize(width: 1210, height: 834), insets: Self.insets)
        let small = grid.tileSize(.small)
        #expect(grid.tileSize(.medium).width == small.width * 2 + FaceGrid.gap)
        #expect(grid.tileSize(.medium).height == small.height)
        #expect(grid.tileSize(.large) == CGSize(width: small.width * 2 + FaceGrid.gap, height: small.height * 2 + FaceGrid.gap))
        let second = grid.frame(for: FaceGridCell(column: 1, row: 1))
        #expect(abs(second.minX - (Self.insets.leading + small.width + FaceGrid.gap)) < 0.01)
        #expect(abs(second.minY - (Self.insets.top + small.height + FaceGrid.gap)) < 0.01)
    }

    @Test func contentBlocksTheCellsItCovers() {
        let size = CGSize(width: 1210, height: 834)
        let region = FaceContentRegion.content(landscape: [CGRect(x: 0, y: 0, width: 1, height: 0.5)], portrait: [])
        let grid = FaceGrid(size: size, insets: Self.insets, protecting: region.rects(configuration: FaceConfiguration(faceID: "test"), size: size, insets: Self.insets))
        // The top two of four rows, every column, and nothing else.
        let expected = Set((0..<2).flatMap { row in (0..<6).map { FaceGridCell(column: $0, row: row) } })
        #expect(grid.blocked == expected)
        #expect(grid.openCells.count == 12)
        #expect(!grid.isOpen(FaceGridArea(column: 0, row: 1, columns: 2, rows: 2)))
        #expect(grid.isOpen(FaceGridArea(column: 0, row: 2, columns: 2, rows: 2)))
    }

    @Test func contentThatOnlyGrazesACellLeavesItOpen() {
        let size = CGSize(width: 1210, height: 834)
        let grid = FaceGrid(size: size, insets: Self.insets)
        let cell = grid.frame(for: FaceGridCell(column: 2, row: 2))
        // A few points into the cell, less than the tolerance.
        let grazing = CGRect(x: cell.minX - 100, y: cell.minY - 100, width: 104, height: 104)
        let grazed = FaceGrid(size: size, insets: Self.insets, protecting: [grazing])
        #expect(!grazed.blocked.contains(FaceGridCell(column: 2, row: 2)))
        // Well into it, it is blocked.
        let covering = CGRect(x: cell.minX - 100, y: cell.minY - 100, width: 140, height: 140)
        let covered = FaceGrid(size: size, insets: Self.insets, protecting: [covering])
        #expect(covered.blocked.contains(FaceGridCell(column: 2, row: 2)))
    }

    @Test func aWidgetTooBigForTheOpenCellsHasNoRoom() {
        let size = CGSize(width: 1210, height: 834)
        // Only the leading column is open: room for small widgets alone.
        let region = FaceContentRegion.content(landscape: [CGRect(x: 0.2, y: 0, width: 0.8, height: 1)], portrait: [])
        let grid = FaceGrid(size: size, insets: Self.insets, protecting: region.rects(configuration: FaceConfiguration(faceID: "test"), size: size, insets: Self.insets))
        #expect(grid.hasRoom(for: .small))
        #expect(!grid.hasRoom(for: .medium))
        #expect(!grid.hasRoom(for: .large))
        #expect(grid.openAreas(for: .small).map(\.column) == [0, 0, 0, 0])
    }

    @Test func fillBandsStartAtTheirEdge() {
        #expect(FaceGridFill.readingOrder.bands(columns: 6, rows: 4) == [FaceGridFill.Band()])
        #expect(FaceGridFill.bottomRows.bands(columns: 6, rows: 4).map(\.fromRow) == [3, 2, 1, 0])
        #expect(FaceGridFill.trailingColumns.bands(columns: 6, rows: 4).map(\.fromColumn) == [5, 4, 3, 2, 1, 0])
        let band = FaceGridFill.Band(fromColumn: 4, fromRow: 0)
        #expect(band.contains(FaceGridArea(column: 4, row: 2, columns: 2, rows: 1)))
        #expect(!band.contains(FaceGridArea(column: 3, row: 0, columns: 2, rows: 1)))
    }

    @MainActor @Test func everyFaceButSmartRotationLeavesRoomForAWidgetOnEveryIPad() {
        for definition in FaceCatalog.all {
            let support = definition.widgets
            guard support.allowsWidgets else {
                #expect(definition.id == RotationEngine.selfID)
                continue
            }
            for screen in Self.screens {
                let grid = support.grid(configuration: FaceConfiguration(faceID: definition.id), size: screen,
                                        insets: Self.insets)
                #expect(grid.hasRoom(for: .small), "\(definition.id) \(screen)")
            }
        }
    }
}
