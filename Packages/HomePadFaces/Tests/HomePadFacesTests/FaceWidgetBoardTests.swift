import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Arranging, adding, moving, resizing and dropping widgets on a face's grid.
@Suite struct FaceWidgetBoardTests {
    static let landscape = CGSize(width: 1210, height: 834)
    static let insets = Theme.Spacing.screenContent

    /// A landscape 11-inch grid, with the top half blocked when `clock` is true.
    static func grid(clock: Bool = false, size: CGSize = landscape) -> FaceGrid {
        let region = FaceContentRegion.content(landscape: [CGRect(x: 0, y: 0, width: 1, height: 0.5)],
                                               portrait: [CGRect(x: 0, y: 0, width: 1, height: 0.5)])
        return FaceGrid(size: size, insets: insets, protecting: clock ? region.rects(configuration: FaceConfiguration(faceID: "test"), size: size, insets: insets) : [])
    }

    static func cell(_ column: Int, _ row: Int) -> FaceGridCell { FaceGridCell(column: column, row: row) }

    static func placement(_ name: String, _ size: WidgetSize, _ cell: FaceGridCell? = nil) -> FaceWidgetPlacement {
        FaceWidgetPlacement(id: id(name), widgetID: name, size: size, cell: cell)
    }

    /// A fixed ID per name, so tests can find a widget.
    static func id(_ name: String) -> UUID {
        let hex = name.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } & 0xFFFF_FFFF_FFFF
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llX", hex))!
    }

    static func board(_ placements: [FaceWidgetPlacement], clock: Bool = false, fill: FaceGridFill = .readingOrder) -> FaceWidgetBoard {
        FaceWidgetBoard(placements: placements, grid: grid(clock: clock), fill: fill)
    }

    static func origin(_ board: FaceWidgetBoard?, _ name: String) -> FaceGridCell? {
        board?.item(id(name))?.area.origin
    }

    /// No widget covers another or a blocked cell, and each lies inside the grid.
    static func isValid(_ board: FaceWidgetBoard) -> Bool {
        var taken = Set<FaceGridCell>()
        for item in board.items {
            guard board.grid.isOpen(item.area) else { return false }
            for cell in item.area.cells {
                guard taken.insert(cell).inserted else { return false }
            }
        }
        return true
    }

    // MARK: Arranging saved widgets

    @Test func widgetsPlacedByHandKeepTheirCells() {
        let board = Self.board([Self.placement("a", .medium, Self.cell(3, 1)), Self.placement("b", .small, Self.cell(0, 3))])
        #expect(Self.origin(board, "a") == Self.cell(3, 1))
        #expect(Self.origin(board, "b") == Self.cell(0, 3))
        #expect(board.leftOut.isEmpty)
    }

    @Test func widgetsWithoutACellFillInTheFaceOrder() {
        let names = ["a", "b", "c"]
        let bottom = Self.board(names.map { Self.placement($0, .medium) }, fill: .bottomRows)
        #expect(names.map { Self.origin(bottom, $0) } == [Self.cell(0, 3), Self.cell(2, 3), Self.cell(4, 3)])
        let column = Self.board(names.map { Self.placement($0, .medium) }, fill: .trailingColumns)
        #expect(names.map { Self.origin(column, $0) } == [Self.cell(4, 0), Self.cell(4, 1), Self.cell(4, 2)])
        let reading = Self.board(names.map { Self.placement($0, .small) }, fill: .readingOrder)
        #expect(names.map { Self.origin(reading, $0) } == [Self.cell(0, 0), Self.cell(1, 0), Self.cell(2, 0)])
    }

    @Test func widgetsWithoutACellKeepTheirOrderAgainstTheEdge() {
        // Three mediums need two rows along the bottom of a portrait grid: they
        // fill them in reading order rather than the bottom row first.
        let grid = FaceGrid(size: CGSize(width: 834, height: 1210), insets: Self.insets)
        let names = ["a", "b", "c"]
        let board = FaceWidgetBoard(placements: names.map { Self.placement($0, .medium) }, grid: grid, fill: .bottomRows)
        #expect(names.map { Self.origin(board, $0) } == [Self.cell(0, 4), Self.cell(2, 4), Self.cell(0, 5)])
        // Down the trailing column, in reading order too.
        let column = Self.board(names.map { Self.placement($0, .small) }, fill: .trailingColumns)
        #expect(names.map { Self.origin(column, $0) } == [Self.cell(5, 0), Self.cell(5, 1), Self.cell(5, 2)])
    }

    @Test func aWidgetOverlappingAnEarlierOneOrTheClockMovesToTheFirstFreeArea() {
        let board = Self.board([
            Self.placement("a", .large, Self.cell(0, 2)),
            Self.placement("b", .small, Self.cell(1, 3)), // under a
            Self.placement("c", .small, Self.cell(2, 0)), // on the clock
        ], clock: true, fill: .bottomRows)
        #expect(Self.origin(board, "a") == Self.cell(0, 2))
        #expect(Self.origin(board, "b") == Self.cell(2, 3))
        #expect(Self.origin(board, "c") == Self.cell(3, 3))
        #expect(Self.isValid(board))
    }

    @Test func aWidgetWithNoRoomAtItsSizeStepsDownAndThenWaits() {
        // With the top half blocked, the bottom holds two larges and two smalls
        // placed so no medium fits: a large with no cell steps down to small.
        let pinned = [
            Self.placement("l1", .large, Self.cell(0, 2)), Self.placement("l2", .large, Self.cell(2, 2)),
            Self.placement("s1", .small, Self.cell(4, 2)), Self.placement("s2", .small, Self.cell(5, 3)),
        ]
        let board = Self.board(pinned + [Self.placement("big", .large)], clock: true)
        #expect(board.item(Self.id("big"))?.size == .small)
        #expect(Self.origin(board, "big") == Self.cell(5, 2))
        // Once the face is full, the next waits, saved as it was.
        let full = Self.board(pinned + [Self.placement("big", .large), Self.placement("last", .small),
                                        Self.placement("more", .medium)], clock: true)
        #expect(Self.origin(full, "last") == Self.cell(4, 3))
        #expect(full.leftOut.map(\.widgetID) == ["more"])
        #expect(full.placements.map(\.widgetID) == ["l1", "l2", "s1", "s2", "big", "last", "more"])
        #expect(full.placements.last?.size == .medium)
    }

    @Test func aWidgetSmallerThanItsSmallestSizeTakesItsSmallestSize() {
        let board = FaceWidgetBoard(placements: [Self.placement("wide", .small)], grid: Self.grid(), fill: .readingOrder,
                                    sizes: { _ in [.medium, .large] })
        #expect(board.items.first?.size == .medium)
    }

    @Test func widgetsWhoseModuleIsGoneStaySavedButTakeNoRoom() {
        let board = FaceWidgetBoard(placements: [Self.placement("gone", .large, Self.cell(0, 0)), Self.placement("here", .small)],
                                    grid: Self.grid(), fill: .readingOrder,
                                    sizes: { $0 == "gone" ? [] : WidgetSize.allCases })
        #expect(board.items.map(\.widgetID) == ["here"])
        #expect(Self.origin(board, "here") == Self.cell(0, 0))
        #expect(board.placements.map(\.widgetID) == ["here", "gone"])
        #expect(board.placements.last?.cell == Self.cell(0, 0))
    }

    @Test func placementsPinEveryWidgetToItsCell() {
        let board = Self.board([Self.placement("a", .small), Self.placement("b", .medium)], fill: .bottomRows)
        #expect(board.placements.map(\.cell) == [Self.cell(0, 3), Self.cell(1, 3)])
        // Arranging the saved placements again gives the same board.
        #expect(Self.board(board.placements, fill: .bottomRows) == board)
    }

    // MARK: Adding and removing

    @Test func aNewWidgetGoesInTheFirstFreeAreaOrNowhere() {
        var board = Self.board([], clock: true, fill: .bottomRows)
        for index in 0..<3 {
            guard let next = board.adding("w\(index)", size: .medium) else {
                Issue.record("no room for medium \(index)")
                return
            }
            board = next
        }
        #expect(board.items.map(\.area.origin) == [Self.cell(0, 3), Self.cell(2, 3), Self.cell(4, 3)])
        // The bottom row is full, so a large has no room, and a medium goes above.
        #expect(!board.hasRoom(for: .large))
        #expect(board.adding("big", size: .large) == nil)
        board = board.adding("next", size: .medium, id: Self.id("next"))!
        #expect(Self.origin(board, "next") == Self.cell(0, 2))
        #expect(Self.isValid(board))
    }

    @Test func removingTakesOnlyThatWidget() {
        let board = Self.board([Self.placement("a", .small), Self.placement("b", .small)])
        #expect(board.removing(Self.id("a")).items.map(\.widgetID) == ["b"])
        #expect(board.removing(Self.id("nothing")) == board)
    }

    // MARK: Moving

    @Test func aWidgetMovesToAFreeArea() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3))], clock: true)
        let moved = board.moving(Self.id("a"), to: Self.cell(5, 2))
        #expect(Self.origin(moved, "a") == Self.cell(5, 2))
    }

    @Test func aWidgetCannotCoverTheClockOrLeaveTheGrid() {
        let board = Self.board([Self.placement("a", .medium, Self.cell(0, 3))], clock: true)
        #expect(board.moving(Self.id("a"), to: Self.cell(0, 1)) == nil)
        #expect(board.moving(Self.id("a"), to: Self.cell(5, 3)) == nil)
        #expect(board.moving(Self.id("a"), to: Self.cell(0, 4)) == nil)
        #expect(board.moving(Self.id("a"), to: Self.cell(-1, 3)) == nil)
    }

    @Test func droppingOnAWidgetPushesItToTheNearestFreeArea() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3)), Self.placement("b", .small, Self.cell(1, 3))], clock: true)
        // a onto b: b takes the cell a left, the nearest free one.
        let swapped = board.moving(Self.id("a"), to: Self.cell(1, 3))
        #expect(Self.origin(swapped, "a") == Self.cell(1, 3))
        #expect(Self.origin(swapped, "b") == Self.cell(0, 3))
        // A medium onto two smalls pushes both.
        let wide = Self.board([Self.placement("m", .medium, Self.cell(4, 2)), Self.placement("a", .small, Self.cell(0, 3)),
                               Self.placement("b", .small, Self.cell(1, 3))], clock: true)
        let pushed = wide.moving(Self.id("m"), to: Self.cell(0, 3))
        #expect(Self.origin(pushed, "m") == Self.cell(0, 3))
        #expect(pushed.map(Self.isValid) == true)
        // Cells are a little wider than tall, so the cell beside is nearer than the one above.
        #expect(Self.origin(pushed, "a") == Self.cell(0, 2))
        #expect(Self.origin(pushed, "b") == Self.cell(2, 3))
    }

    @Test func aMoveIsRefusedWhenAPushedWidgetHasNowhereToGo() {
        // The bottom half holds three larges: nothing can make room for another.
        let board = Self.board([Self.placement("a", .large, Self.cell(0, 2)), Self.placement("b", .large, Self.cell(2, 2)),
                                Self.placement("c", .large, Self.cell(4, 2))], clock: true)
        #expect(board.moving(Self.id("a"), to: Self.cell(1, 2)) == nil)
        // Onto another large's exact place they trade.
        let traded = board.moving(Self.id("a"), to: Self.cell(2, 2))
        #expect(Self.origin(traded, "b") == Self.cell(0, 2))
    }

    @Test func movingNeverChangesTheOrderOfWidgets() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3)), Self.placement("b", .small, Self.cell(1, 3))])
        let moved = board.moving(Self.id("b"), to: Self.cell(0, 3))
        #expect(moved?.items.map(\.widgetID) == ["a", "b"])
    }

    // MARK: Resizing

    @Test func resizingKeepsTheTopLeadingCellWhenItFits() {
        let board = Self.board([Self.placement("a", .small, Self.cell(1, 2))], clock: true)
        #expect(board.resizing(Self.id("a"), to: .medium)?.item(Self.id("a"))?.area
                == FaceGridArea(column: 1, row: 2, columns: 2, rows: 1))
        #expect(board.resizing(Self.id("a"), to: .large)?.item(Self.id("a"))?.area
                == FaceGridArea(column: 1, row: 2, columns: 2, rows: 2))
    }

    @Test func resizingAtAnEdgeGrowsBackJustEnough() {
        let board = Self.board([Self.placement("a", .small, Self.cell(5, 3))], clock: true)
        // No room to the right or below: it grows toward the leading edge and up.
        #expect(board.resizing(Self.id("a"), to: .large)?.item(Self.id("a"))?.area
                == FaceGridArea(column: 4, row: 2, columns: 2, rows: 2))
    }

    @Test func resizingPushesNeighborsAsideAndShrinkingKeepsTheCorner() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3)), Self.placement("b", .small, Self.cell(1, 3))], clock: true)
        let grown = board.resizing(Self.id("a"), to: .medium)
        #expect(grown?.item(Self.id("a"))?.area == FaceGridArea(column: 0, row: 3, columns: 2, rows: 1))
        #expect(grown.map(Self.isValid) == true)
        #expect(Self.origin(grown, "b") == Self.cell(2, 3))
        let large = Self.board([Self.placement("a", .large, Self.cell(2, 2))])
        #expect(large.resizing(Self.id("a"), to: .small)?.item(Self.id("a"))?.area.origin == Self.cell(2, 2))
    }

    @Test func resizingIsRefusedWithoutRoom() {
        // Only one open row: a large never fits.
        let size = Self.landscape
        let region = FaceContentRegion.content(landscape: [CGRect(x: 0, y: 0, width: 1, height: 0.7)], portrait: [])
        let grid = FaceGrid(size: size, insets: Self.insets, protecting: region.rects(configuration: FaceConfiguration(faceID: "test"), size: size, insets: Self.insets))
        let board = FaceWidgetBoard(placements: [Self.placement("a", .small, Self.cell(2, 3))], grid: grid, fill: .bottomRows)
        #expect(board.resizing(Self.id("a"), to: .large) == nil)
        #expect(board.resizing(Self.id("a"), to: .medium) != nil)
    }

    // MARK: Dragging

    private func center(_ grid: FaceGrid, _ cell: FaceGridCell, _ size: WidgetSize, dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        let frame = grid.frame(for: FaceGridArea(origin: cell, size: size))
        return CGPoint(x: frame.midX + dx, y: frame.midY + dy)
    }

    @Test func aDraggedWidgetSnapsToTheNearestArea() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3))], clock: true)
        let grid = board.grid
        // A little past the middle of the cell two to the right.
        let target = board.dropOrigin(for: Self.id("a"), center: center(grid, Self.cell(2, 3), .small, dx: 30, dy: -20),
                                      current: Self.cell(0, 3))
        #expect(target == Self.cell(2, 3))
    }

    @Test func overTheClockADraggedWidgetLandsBesideIt() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3))], clock: true)
        let target = board.dropOrigin(for: Self.id("a"), center: center(board.grid, Self.cell(3, 0), .small),
                                      current: Self.cell(0, 3))
        // The nearest open row is the third.
        #expect(target == Self.cell(3, 2))
    }

    @Test func theCurrentAreaHoldsNearTheLineBetweenTwo() {
        let board = Self.board([Self.placement("a", .small, Self.cell(0, 3))])
        let grid = board.grid
        // Just past halfway to the next cell.
        let step = grid.cellSize.width + grid.gap
        let point = center(grid, Self.cell(1, 3), .small, dx: step / 2 + 4)
        #expect(board.dropOrigin(for: Self.id("a"), center: point, current: Self.cell(1, 3)) == Self.cell(1, 3))
        // Well past it, the next area takes over.
        let farther = center(grid, Self.cell(1, 3), .small, dx: step * 0.9)
        #expect(board.dropOrigin(for: Self.id("a"), center: farther, current: Self.cell(1, 3)) == Self.cell(2, 3))
    }

    @Test func theResizeHandleSnapsToTheNearestSupportedSize() {
        let board = Self.board([Self.placement("a", .small, Self.cell(1, 2))], clock: true)
        let grid = board.grid
        let small = grid.frame(for: FaceGridArea(origin: Self.cell(1, 2), size: .small))
        let medium = grid.frame(for: FaceGridArea(origin: Self.cell(1, 2), size: .medium))
        let large = grid.frame(for: FaceGridArea(origin: Self.cell(1, 2), size: .large))
        let sizes = WidgetSize.allCases
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: medium.maxX - 10, y: medium.maxY + 10),
                                   sizes: sizes, current: .small) == .medium)
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: large.maxX, y: large.maxY),
                                   sizes: sizes, current: .medium) == .large)
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: small.maxX + 5, y: small.maxY),
                                   sizes: sizes, current: .large) == .small)
        // A size the widget does not support is never chosen.
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: large.maxX, y: large.maxY),
                                   sizes: [.small, .medium], current: .small) == .medium)
    }

    /// Tall covers two columns and three rows, grows up at the bottom edge,
    /// and steps down to large where no three rows are open.
    @Test func aTallWidgetTakesThreeRowsAndStepsDownWithoutThem() {
        let tall = Self.board([Self.placement("a", .large, Self.cell(4, 1))]).resizing(Self.id("a"), to: .tall)
        #expect(tall?.item(Self.id("a"))?.area == FaceGridArea(column: 4, row: 1, columns: 2, rows: 3))
        let low = Self.board([Self.placement("a", .large, Self.cell(4, 2))]).resizing(Self.id("a"), to: .tall)
        #expect(low?.item(Self.id("a"))?.area == FaceGridArea(column: 4, row: 1, columns: 2, rows: 3))
        // The clock takes the top two rows, so a tall widget saved there shows large and stays saved.
        let blocked = Self.board([Self.placement("b", .tall, Self.cell(0, 2))], clock: true)
        #expect(blocked.item(Self.id("b"))?.size == .large)
        #expect(blocked.leftOut.isEmpty)
        #expect(!blocked.grid.hasRoom(for: .tall))
    }

    @Test func theResizeHandleReachesTall() {
        let board = Self.board([Self.placement("a", .large, Self.cell(4, 0))])
        let tall = board.grid.frame(for: FaceGridArea(origin: Self.cell(4, 0), size: .tall))
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: tall.maxX, y: tall.maxY),
                                   sizes: WidgetSize.allCases, current: .large) == .tall)
        // A widget without tall never takes it.
        #expect(board.resizeTarget(for: Self.id("a"), corner: CGPoint(x: tall.maxX, y: tall.maxY),
                                   sizes: WidgetSize.standard, current: .large) == .large)
    }

    // MARK: Invariants

    @Test func noSequenceOfChangesEverOverlapsWidgetsOrCoversTheClock() {
        var random = SplitMix(seed: 7)
        func pick(_ count: Int) -> Int { Int(random.next() % UInt64(max(count, 1))) }
        for size in [Self.landscape, CGSize(width: 834, height: 1210), CGSize(width: 1376, height: 1032)] {
            var board = FaceWidgetBoard(placements: [], grid: Self.grid(clock: true, size: size), fill: .bottomRows)
            for step in 0..<400 {
                let sizes = WidgetSize.allCases
                switch pick(4) {
                case 0:
                    board = board.adding("w\(step)", size: sizes[pick(sizes.count)]) ?? board
                case 1 where !board.items.isEmpty:
                    let item = board.items[pick(board.items.count)]
                    board = board.moving(item.id, to: FaceGridCell(column: pick(7) - 1, row: pick(7) - 1)) ?? board
                case 2 where !board.items.isEmpty:
                    let item = board.items[pick(board.items.count)]
                    board = board.resizing(item.id, to: sizes[pick(sizes.count)]) ?? board
                case 3 where board.items.count > 3:
                    board = board.removing(board.items[pick(board.items.count)].id)
                default:
                    break
                }
                #expect(Self.isValid(board), "\(size) step \(step)")
            }
        }
    }
}
