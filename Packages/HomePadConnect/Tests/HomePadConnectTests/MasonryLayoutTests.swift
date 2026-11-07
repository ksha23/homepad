import CoreGraphics
import Testing
@testable import HomePadConnect

@Suite struct MasonryLayoutTests {
    // MARK: Columns

    /// The board's content width on each iPad (the screen less 64 points a side),
    /// with the board's 240 point ideal and 16 point gap.
    @Test(arguments: [
        (1082.0, 4),  // 11-inch landscape
        (1248.0, 5),  // 13-inch landscape
        (706.0, 3),   // 11-inch portrait
        (904.0, 4),   // 13-inch portrait
    ])
    func boardColumnsOnEachIPad(width: Double, expected: Int) {
        let columns = MasonryColumns(width: width, ideal: 240, spacing: 16)
        #expect(columns.count == expected)
        #expect(columns.width >= 240 * 0.8 && columns.width <= 270)
        #expect(abs(columns.totalWidth(spacing: 16) - width) < 0.001)
    }

    @Test func noWidthMeansOneIdealColumn() {
        let columns = MasonryColumns(width: nil, ideal: 150, spacing: 10)
        #expect(columns == MasonryColumns(width: 150, ideal: 150, spacing: 10))
        #expect(columns.count == 1)
    }

    @Test func roundingNeverSqueezesColumnsBelowFourFifths() {
        // 380 rounds to two columns of 182, too narrow for a 240 point note.
        let columns = MasonryColumns(width: 380, ideal: 240, spacing: 16)
        #expect(columns.count == 1)
        #expect(columns.width == 380)
        #expect(MasonryColumns(width: 400, ideal: 240, spacing: 16).count == 2)
    }

    @Test func narrowSpaceStillGetsOneColumn() {
        let columns = MasonryColumns(width: 100, ideal: 240, spacing: 16)
        #expect(columns.count == 1)
        #expect(columns.width == 100)
    }

    // MARK: Packing

    @Test func firstItemsRunLeftToRight() {
        let packing = MasonryPacking(heights: [50, 50, 50], columns: 3, spacing: 10)
        #expect(packing.slots.map(\.column) == [0, 1, 2])
        #expect(packing.slots.allSatisfy { $0.y == 0 })
        #expect(packing.height == 50)
    }

    @Test func eachItemGoesUnderTheShortestColumn() {
        let packing = MasonryPacking(heights: [100, 50, 80, 30], columns: 2, spacing: 10)
        #expect(packing.slots == [
            .init(column: 0, y: 0),
            .init(column: 1, y: 0),
            .init(column: 1, y: 60),
            .init(column: 0, y: 110),
        ])
        #expect(packing.height == 140)
    }

    @Test func noItemsHaveNoHeight() {
        #expect(MasonryPacking(heights: [], columns: 4, spacing: 16).height == 0)
    }
}
