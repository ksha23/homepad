import CoreGraphics
import HomePadCore
import Testing
@testable import HomePadShell

/// 100 point cells with no gaps, so a cell's center is easy to name.
private func frame(_ placement: GridPlacement) -> CGRect {
    CGRect(x: placement.column * 100, y: placement.row * 100,
           width: placement.span.columns * 100, height: placement.span.rows * 100)
}

/// The center of a cell in that grid.
private func cell(_ column: Int, _ row: Int) -> CGPoint {
    CGPoint(x: column * 100 + 50, y: row * 100 + 50)
}

private let large = GridSpan(.large)
private let medium = GridSpan(.medium)

@Suite struct GridReorderTests {
    @Test func eachPlaceInTheOrderGivesOneSlot() {
        let reorder = GridReorder(others: [.one, .one, .one], dragged: .one, columns: 4, rows: 2)
        #expect(reorder.slots().map(\.placement.column) == [0, 1, 2, 3])
        #expect(reorder.slots().allSatisfy { $0.page == 0 && $0.placement.row == 0 })
    }

    @Test func theTargetIsTheSlotUnderTheItem() {
        let reorder = GridReorder(others: [.one, .one, .one], dragged: .one, columns: 4, rows: 2)
        #expect(reorder.target(for: cell(2, 0), onPage: 0, current: 0, hysteresis: 25, frame: frame) == 2)
        // Below every item, it goes to the end.
        #expect(reorder.target(for: cell(3, 1), onPage: 0, current: 0, hysteresis: 25, frame: frame) == 3)
    }

    @Test func iconsFlowAroundAWidget() {
        // A large widget fills two rows, so the icon after the two beside it lands under them.
        let reorder = GridReorder(others: [large, .one, .one], dragged: .one, columns: 4, rows: 2)
        #expect(reorder.slot(at: 3)?.placement.column == 2)
        #expect(reorder.slot(at: 3)?.placement.row == 1)
        #expect(reorder.target(for: cell(2, 1), onPage: 0, current: nil, hysteresis: 25, frame: frame) == 3)
        // Before the widget, the icon takes its corner and the widget moves over.
        #expect(reorder.target(for: cell(0, 0), onPage: 0, current: nil, hysteresis: 25, frame: frame) == 0)
    }

    @Test func aWidgetTakesASlotOfItsSize() {
        let reorder = GridReorder(others: [.one, .one, .one, .one], dragged: medium, columns: 4, rows: 2)
        // Two cells wide, it fits beside the first two icons but not the third, so
        // over the second row's left half it wraps there and the last icon fills in.
        let center = CGPoint(x: 100, y: 150)
        let index = reorder.target(for: center, onPage: 0, current: nil, hysteresis: 25, frame: frame)
        #expect(index == 3)
        #expect(reorder.slot(at: 3)?.placement == GridPlacement(index: 3, column: 0, row: 1, span: medium))
        #expect(reorder.slot(at: 2)?.placement == GridPlacement(index: 2, column: 2, row: 0, span: medium))
    }

    @Test func hysteresisKeepsTheSlotNearTheLine() {
        let reorder = GridReorder(others: [.one, .one, .one], dragged: .one, columns: 4, rows: 2)
        // Just past the line between the second and third slots: nearer the third, but not by enough.
        let nearLine = CGPoint(x: 205, y: 50)
        #expect(reorder.target(for: nearLine, onPage: 0, current: 1, hysteresis: 25, frame: frame) == 1)
        #expect(reorder.target(for: nearLine, onPage: 0, current: nil, hysteresis: 25, frame: frame) == 2)
        // Well past it, the slot moves.
        #expect(reorder.target(for: CGPoint(x: 235, y: 50), onPage: 0, current: 1, hysteresis: 25, frame: frame) == 2)
    }

    @Test func aWidgetOverIconsNeverFlipsUnderAStillFinger() {
        // A large widget held on the line between two of its slots (one beside the
        // first icon, one a row lower), the finger trembling a few points either way.
        let reorder = GridReorder(others: Array(repeating: .one, count: 8), dragged: large, columns: 4, rows: 4)
        func changes(hysteresis: CGFloat) -> Int {
            var current: Int?
            var changes = 0
            for step in 0..<40 {
                let tremble: CGFloat = step.isMultiple(of: 2) ? -8 : 8
                let next = reorder.target(for: CGPoint(x: 200, y: 150 + tremble), onPage: 0, current: current,
                                          hysteresis: hysteresis, frame: frame)
                if next != current { changes += 1 }
                current = next
            }
            return changes
        }
        #expect(changes(hysteresis: 25) == 1)
        // Without the margin it would flip on every tremble.
        #expect(changes(hysteresis: 0) == 40)
    }

    @Test func onlySlotsOnThePageCount() {
        // Four cells a page and nine items: the second page holds places 4 to 7.
        let reorder = GridReorder(others: Array(repeating: .one, count: 8), dragged: .one, columns: 2, rows: 2)
        #expect(reorder.slots().map(\.page) == [0, 0, 0, 0, 1, 1, 1, 1, 2])
        #expect(reorder.target(for: cell(0, 0), onPage: 1, current: nil, hysteresis: 25, frame: frame) == 4)
        #expect(reorder.target(for: cell(0, 0), onPage: 5, current: nil, hysteresis: 25, frame: frame) == nil)
    }
}

@Suite struct HomeReorderPlannerTests {
    private typealias Item = HomeReorderPlanner.Item
    private typealias Target = HomeReorderPlanner.Target

    private func icons(_ ids: String...) -> [Item] {
        ids.map { Item(id: $0, span: .one) }
    }

    @Test func theOriginLeavesTheItemInPlace() {
        let planner = HomeReorderPlanner(pages: [icons("a", "b", "c")], columns: 4, rows: 2)
        #expect(planner.origin(of: "b") == Target(page: 0, beforeID: "c"))
        #expect(planner.origin(of: "c") == Target(page: 0, beforeID: nil))
        #expect(planner.moving("b", to: Target(page: 0, beforeID: "c")) == planner.pages)
    }

    @Test func movingMatchesTheSavedLayout() {
        let planner = HomeReorderPlanner(pages: [icons("a", "b", "c"), icons("d")], columns: 4, rows: 2)
        let target = Target(page: 1, beforeID: "d")
        var layout = HomeScreenLayout(pages: [[.app("a"), .app("b"), .app("c")], [.app("d")]], knownAppIDs: [])
        layout.move(HomeScreenItem.app("a").id, toPage: target.page, before: HomeScreenItem.app("d").id)
        #expect(layout.pages.map { $0.map(\.targetID) } == [["b", "c"], ["a", "d"]])
        #expect(planner.moving("a", to: target).map { $0.map(\.id) } == [["b", "c"], ["a", "d"]])
        layout.move(HomeScreenItem.app("a").id, toPage: 0, before: nil)
        #expect(layout.pages.map { $0.map(\.targetID) } == [["b", "c", "a"], ["d"]])
    }

    @Test func targetsTheDrawnPageOnScreen() {
        // Two by two: one logical page of six icons draws as a page of four and a page of two.
        let planner = HomeReorderPlanner(pages: [icons("a", "b", "c", "d", "e", "f")], columns: 2, rows: 2)
        let origin = Target(page: 0, beforeID: "b")
        // Over the second drawn page's second cell, "a" goes after "f", at the end.
        let target = planner.target(moving: "a", center: cell(1, 0), onDrawnPage: 1, current: origin,
                                    hysteresis: 25, frame: frame)
        #expect(target == Target(page: 0, beforeID: nil))
        #expect(planner.slot(of: "a", at: target)?.page == 1)
        // Over its first cell, before "f".
        let first = planner.target(moving: "a", center: cell(0, 0), onDrawnPage: 1, current: origin,
                                   hysteresis: 25, frame: frame)
        #expect(first == Target(page: 0, beforeID: "f"))
    }

    @Test func theSamePageIsFoundAfterAMoveDropsAPageBeforeIt() {
        // "e" alone fills the second drawn page of the first logical page. Moving it
        // to the next logical page drops that drawn page, so the page on screen moves up one.
        let planner = HomeReorderPlanner(pages: [icons("a", "b", "c", "d", "e"), icons("f")], columns: 2, rows: 2)
        let origin = Target(page: 0, beforeID: nil)
        let onScreen = planner.drawnPage(at: 2, moving: "e", to: origin)
        #expect(onScreen == HomeReorderPlanner.DrawnPage(page: 1, part: 0))
        let moved = Target(page: 1, beforeID: "f")
        #expect(planner.index(of: HomeReorderPlanner.DrawnPage(page: 1, part: 0), moving: "e", to: moved) == 1)
    }

    @Test func anEmptyPageTakesTheItemInItsFirstSlot() {
        let planner = HomeReorderPlanner(pages: [icons("a", "b"), []], columns: 2, rows: 2)
        let target = planner.target(moving: "a", center: cell(1, 1), onDrawnPage: 1,
                                    current: Target(page: 0, beforeID: "b"), hysteresis: 25, frame: frame)
        #expect(target == Target(page: 1, beforeID: nil))
        #expect(planner.slot(of: "a", at: target)?.placement.column == 0)
    }
}

@Suite struct HomeScreenLayoutPageTests {
    @Test func removesOnlyAnEmptyPage() {
        var layout = HomeScreenLayout(pages: [[.app("a")], [], [.app("b")]], knownAppIDs: [])
        layout.removePageIfEmpty(0)
        #expect(layout.pages.count == 3)
        layout.removePageIfEmpty(1)
        #expect(layout.pages == [[.app("a")], [.app("b")]])
        var single = HomeScreenLayout(pages: [[]], knownAppIDs: [])
        single.removePageIfEmpty(0)
        #expect(single.pages.count == 1)
    }
}
