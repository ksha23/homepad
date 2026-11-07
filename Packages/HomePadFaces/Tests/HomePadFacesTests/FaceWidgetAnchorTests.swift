import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Widgets anchored top leading (the glance) land in the open area nearest a
/// face's top leading corner, and every other widget still goes where it did.
@Suite struct FaceWidgetAnchorTests {
    private typealias Board = FaceWidgetBoardTests

    @Test func anAnchoredWidgetTakesTheTopLeadingCornerWhateverTheFill() {
        let board = Board.board([], fill: .bottomRows)
        let added = board.adding("glance", size: .medium, id: Board.id("glance"), anchor: .topLeading)
        #expect(Board.origin(added, "glance") == Board.cell(0, 0))
        // A widget without the anchor still follows the fill.
        let plain = board.adding("plain", size: .medium, id: Board.id("plain"))
        #expect(Board.origin(plain, "plain") == Board.cell(0, 3))
    }

    @Test func contentInTheTopLeftSendsItToTheNearestOpenArea() {
        // The clock blocks the top two rows, so the nearest open area is the first one under it.
        let board = Board.board([], clock: true, fill: .bottomRows)
        let added = board.adding("glance", size: .small, id: Board.id("glance"), anchor: .topLeading)
        #expect(Board.origin(added, "glance") == Board.cell(0, 2))
    }

    @Test func aBlockedCornerSendsItBesideTheContent() {
        // With only the top leading cell blocked, the cell beside it is nearer than the one under it.
        let region = FaceContentRegion { _, size, insets in
            let grid = FaceGrid(size: size, insets: insets)
            return [grid.frame(for: Board.cell(0, 0))]
        }
        let grid = FaceWidgetSupport.around(region).grid(configuration: FaceConfiguration(faceID: "test"),
                                                           size: Board.landscape, insets: Board.insets)
        let board = FaceWidgetBoard(grid: grid, fill: .bottomRows)
        let added = board.adding("glance", size: .small, id: Board.id("glance"), anchor: .topLeading)
        #expect(Board.origin(added, "glance") == Board.cell(1, 0))
    }

    @Test func addingItMovesNoOtherWidget() {
        let board = Board.board([Board.placement("a", .medium, Board.cell(0, 0)), Board.placement("b", .small, Board.cell(4, 3))])
        let added = board.adding("glance", size: .small, id: Board.id("glance"), anchor: .topLeading)
        #expect(Board.origin(added, "a") == Board.cell(0, 0))
        #expect(Board.origin(added, "b") == Board.cell(4, 3))
        // The cell under the medium is nearer the corner than the one beside it.
        #expect(Board.origin(added, "glance") == Board.cell(0, 1))
        #expect(added.map(Board.isValid) == true)
    }

    @Test func withoutACellItTakesTheCornerAndTheOthersKeepTheirEdge() {
        // The orientation nobody arranged: every widget arrives without a cell.
        let placements = [Board.placement("a", .medium), Board.placement("glance", .small), Board.placement("b", .medium)]
        let board = FaceWidgetBoard(placements: placements, grid: Board.grid(), fill: .bottomRows,
                                    anchors: { $0 == "glance" ? .topLeading : .faceFill })
        #expect(Board.origin(board, "glance") == Board.cell(0, 0))
        #expect(Board.origin(board, "a") == Board.cell(0, 3))
        #expect(Board.origin(board, "b") == Board.cell(2, 3))
        // Saved order is kept, whatever went where first.
        #expect(board.items.map(\.widgetID) == ["a", "glance", "b"])
    }

    @Test func withoutAnAnchorNothingChanges() {
        let placements = [Board.placement("a", .medium), Board.placement("b", .small)]
        let before = FaceWidgetBoard(placements: placements, grid: Board.grid(clock: true), fill: .bottomRows)
        let after = FaceWidgetBoard(placements: placements, grid: Board.grid(clock: true), fill: .bottomRows,
                                    anchors: { _ in .faceFill })
        #expect(before == after)
    }

    /// On Modular, whose clock fills the screen beside a widget column, the
    /// glance goes to the top of that column in landscape and to the first
    /// row along the bottom in portrait.
    @MainActor @Test func onModularItTopsTheWidgetArea() throws {
        let modular = try #require(FaceCatalog.definition("faces.modular"))
        let configuration = FaceConfiguration(faceID: modular.id)
        for size in [Board.landscape, CGSize(width: 834, height: 1210)] {
            let grid = modular.widgets.grid(configuration: configuration, size: size, insets: Board.insets)
            let board = FaceWidgetBoard(grid: grid, fill: modular.widgets.fill(for: grid.orientation))
            let added = board.adding("glance", size: .small, id: Board.id("glance"), anchor: .topLeading)
            let expected = grid.orientation == .landscape ? Board.cell(4, 0) : Board.cell(0, 4)
            #expect(Board.origin(added, "glance") == expected, "\(grid.orientation)")
        }
    }
}
