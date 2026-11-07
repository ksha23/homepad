import HomePadCore
import HomePadUI
import Observation
import SwiftUI

/// A live reorder on the Home Screen in edit mode, as on iPadOS: a short press
/// lifts an icon or widget, it follows the finger, the others move aside at
/// once to open the slot it would land in, and letting go drops it there and
/// saves it. Holding it at a side of the screen turns the page, so it can move
/// to another page, and past the last page a new one opens.
///
/// Held over a widget or stack of its own size, a widget makes a stack, as on
/// iPadOS: the others hold still while it is over that widget, after a
/// moment the widget under it grows a little to say it will take it, and
/// letting go then stacks them (`HomeScreenLayout.stack(_:onto:)`). Moving on
/// across it reorders as before.
///
/// `HomeScreenView` draws its pages from `working(_:)`, so the slot opens as
/// the target changes, and draws the lifted item over them
/// (`HomeReorderLiftedTile`). Only that view reads `translation`, so following
/// the finger redraws nothing else. `HomeReorderGesture` drives it.
@MainActor
@Observable
final class HomeReorderSession {
    /// The item in the air.
    struct Lift {
        let tile: HomeTile
        /// Where it sat when it lifted, in the pager's space.
        let frame: CGRect
    }

    /// What the reorder needs from the Home Screen as drawn. `HomeScreenView`
    /// hands over a new one each time it draws.
    struct Screen {
        let isEditing: Bool
        let memberID: HouseholdMember.ID?
        let layouts: HomeScreenLayoutStore
        /// The saved layout as drawn, without the drag's move.
        let saved: () -> [[HomeReorderPlanner.Item]]
        /// The drawn pages, with the drag's move.
        let pages: [RenderedHomePage]
        let metrics: HomeGridMetrics
        /// The drawn page on screen.
        let page: Int
        /// Where a page's grid starts in the pager's space while it is on screen.
        let gridOrigin: CGPoint
        /// The pager's width, from one side of the screen to the other.
        let width: CGFloat
        /// Scrolls to a drawn page, with the page-turn animation or at once.
        let showPage: (_ page: Int, _ animated: Bool) -> Void
    }

    private(set) var lift: Lift?
    /// Where the lifted item would land now. Nil when nothing is lifted.
    private(set) var target: HomeReorderPlanner.Target?
    /// True while the item is in the air: drawn larger, and the slot follows it.
    private(set) var isLifted = false
    /// How far the lifted item has moved from where it lifted.
    private(set) var translation: CGSize = .zero
    /// The widget or stack the lifted widget would join as a stack if let go now.
    private(set) var stackTargetID: String?

    /// The Home Screen as last drawn.
    @ObservationIgnored var screen: Screen?
    /// True while the pages scroll. An item lifts only from a page at rest.
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored private var planner: HomeReorderPlanner?
    @ObservationIgnored private var origin: HomeReorderPlanner.Target?
    @ObservationIgnored private var start: CGPoint = .zero
    @ObservationIgnored private var location: CGPoint = .zero
    @ObservationIgnored private var edge: (step: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var isTurningPage = false
    /// The logical page this drag opened past the last one, if any.
    @ObservationIgnored private var addedPage: Int?
    /// Counts lifts, so a settle that finishes late never ends the next drag.
    @ObservationIgnored private var generation = 0
    /// The widget the lifted one rests over, before it offers to stack with it.
    @ObservationIgnored private var pendingStack: (id: String, task: Task<Void, Never>)?

    /// How long a still press takes to lift an item. Short, so a quick swipe still turns the page.
    static let liftDelay: TimeInterval = 0.15
    /// How much larger the lifted item is drawn.
    static let liftScale: CGFloat = 1.08
    /// How long the item is held at a side of the screen before the page turns.
    static let edgeDelay: Duration = .milliseconds(600)
    /// How long a page turn takes to come to rest (`Theme.Motion.screen`).
    static let pageTurn: Duration = .milliseconds(550)
    /// How long a widget rests over another of its size before it offers to
    /// stack with it. Long enough that a widget passing over others to a new
    /// slot never stacks, shorter than a page turn's hold at the screen's side.
    static let stackDelay: Duration = .milliseconds(400)
    /// How much larger the widget that would take the stack is drawn.
    static let stackTargetScale: CGFloat = 1.05

    /// True from the lift until the dropped item has settled into its slot.
    var isActive: Bool { lift != nil }

    /// The layout to draw: the saved one with the lifted item at its target.
    func working(_ layout: HomeScreenLayout) -> HomeScreenLayout {
        guard let lift, let target else { return layout }
        var moved = layout
        moved.move(lift.tile.id, toPage: target.page, before: target.beforeID)
        return moved
    }

    /// True when a press at `point`, in the pager's space, would lift an item.
    func canLift(at point: CGPoint) -> Bool {
        screen?.isEditing == true && lift == nil && !isScrolling && hit(at: point) != nil
    }

    /// Lifts the item under `point`.
    func begin(at point: CGPoint) {
        guard canLift(at: point), let screen, let hit = hit(at: point) else { return }
        let planner = HomeReorderPlanner(pages: screen.saved(), columns: screen.metrics.columns, rows: screen.metrics.rows)
        guard let origin = planner.origin(of: hit.tile.id) else { return }
        self.planner = planner
        self.origin = origin
        generation += 1
        start = point
        location = point
        translation = .zero
        // At once, so the item never shows twice. Only the lift itself animates.
        lift = Lift(tile: hit.tile, frame: hit.frame)
        target = origin
        withAnimation(Theme.Motion.settle) { isLifted = true }
    }

    /// The finger moved: the item follows it exactly and the slot follows the item.
    func move(to point: CGPoint) {
        guard isLifted else { return }
        location = point
        translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        retarget()
        watchEdges()
    }

    /// The finger let go: saves the slot the item is over and lets it settle there.
    func drop(at point: CGPoint) {
        // A quick flick reports where it ended only here.
        move(to: point)
        stopWatchingEdges()
        guard isLifted, let lift, let target, let screen else { return }
        if let stackID = stackTargetID, let planner {
            var stacked: String?
            screen.layouts.update(for: screen.memberID) { stacked = $0.stack(lift.tile.id, onto: stackID) }
            if let stacked {
                // It settles into the stack it joined.
                self.planner = planner.stacking(lift.tile.id, onto: stackID, as: stacked)
                let slot = self.planner?.origin(of: stacked).flatMap { slotFrame(of: stacked, at: $0) }
                self.target = nil
                stopWaitingToStack()
                settle(into: slot)
                return
            }
        }
        if target != origin {
            screen.layouts.update(for: screen.memberID) {
                $0.move(lift.tile.id, toPage: target.page, before: target.beforeID)
            }
        }
        // The saved layout has the move now, so drawing it again changes nothing.
        let slot = slotFrame(of: lift.tile.id, at: target)
        self.target = nil
        settle(into: slot)
    }

    /// The press ended some other way (edit mode ended, the system took the touch):
    /// everything goes back where it was and nothing is saved.
    func cancel() {
        stopWatchingEdges()
        stopWaitingToStack()
        guard isLifted, let lift, let origin else { return end() }
        let slot = slotFrame(of: lift.tile.id, at: origin)
        withAnimation(Theme.Motion.settle) { target = nil }
        settle(into: slot)
    }

    // MARK: Slots

    /// Points another slot must be nearer by before the item leaves its own.
    static func hysteresis(for metrics: HomeGridMetrics) -> CGFloat {
        min(metrics.cellSize.width, metrics.cellSize.height) / 4
    }

    private func retarget() {
        guard let lift, let target, let planner, let screen, !isTurningPage else { return }
        let frame = lift.frame.offsetBy(dx: translation.width, dy: translation.height)
        let center = CGPoint(x: frame.midX - screen.gridOrigin.x, y: frame.midY - screen.gridOrigin.y)
        if let under = planner.stackTarget(moving: lift.tile.id, center: center, onDrawnPage: screen.page,
                                           current: target, frame: screen.metrics.frame(for:)) {
            // Over a widget of its size the others hold still, so the widget stays under the finger to stack with.
            waitToStack(on: under)
            return
        }
        stopWaitingToStack()
        let next = planner.target(
            moving: lift.tile.id, center: center, onDrawnPage: screen.page, current: target,
            hysteresis: Self.hysteresis(for: screen.metrics), frame: screen.metrics.frame(for:)
        )
        guard next != target else { return }
        let onScreen = planner.drawnPage(at: screen.page, moving: lift.tile.id, to: target)
        withAnimation(Theme.Motion.settle) { self.target = next }
        // Moving the item to another logical page can add or drop a page before
        // this one. The same page stays on screen.
        if let onScreen, let index = planner.index(of: onScreen, moving: lift.tile.id, to: next), index != screen.page {
            screen.showPage(index, false)
        }
    }

    /// The slot's frame in the pager's space, or nil when it is not on the page on screen.
    private func slotFrame(of itemID: String, at target: HomeReorderPlanner.Target) -> CGRect? {
        guard let planner, let screen, let slot = planner.slot(of: itemID, at: target), slot.page == screen.page else {
            return nil
        }
        return screen.metrics.frame(for: slot.placement).offsetBy(dx: screen.gridOrigin.x, dy: screen.gridOrigin.y)
    }

    /// The item lands in `slot` and the drag ends. Off screen it just ends.
    private func settle(into slot: CGRect?) {
        guard let lift, let slot else { return end() }
        let generation = generation
        withAnimation(Theme.Motion.settle, completionCriteria: .logicallyComplete) {
            isLifted = false
            translation = CGSize(width: slot.minX - lift.frame.minX, height: slot.minY - lift.frame.minY)
        } completion: { [weak self] in
            if self?.generation == generation { self?.end() }
        }
    }

    private func end() {
        stopWatchingEdges()
        stopWaitingToStack()
        // A page the drag opened goes again unless the item landed there.
        if let addedPage, let screen {
            screen.layouts.update(for: screen.memberID) { $0.removePageIfEmpty(addedPage) }
        }
        addedPage = nil
        lift = nil
        target = nil
        isLifted = false
        translation = .zero
        planner = nil
        origin = nil
    }

    /// The item drawn at `point` on the page on screen, and its frame in the pager's space.
    private func hit(at point: CGPoint) -> (tile: HomeTile, frame: CGRect)? {
        guard let screen, screen.pages.indices.contains(screen.page) else { return nil }
        for entry in screen.pages[screen.page].tiles {
            let frame = screen.metrics.frame(for: entry.placement).offsetBy(dx: screen.gridOrigin.x, dy: screen.gridOrigin.y)
            if frame.contains(point) { return (entry.tile, frame) }
        }
        return nil
    }

    // MARK: Stacking

    /// The lifted widget rests over another of its size: after `stackDelay`
    /// that one grows a little, and letting go then stacks them.
    private func waitToStack(on id: String) {
        guard stackTargetID != id, pendingStack?.id != id else { return }
        stopWaitingToStack()
        let task = Task { [weak self] in
            try? await Task.sleep(for: Self.stackDelay)
            guard !Task.isCancelled, let self, self.isLifted else { return }
            self.pendingStack = nil
            withAnimation(Theme.Motion.settle) { self.stackTargetID = id }
        }
        pendingStack = (id, task)
    }

    /// The lifted widget left the one it rested over, or the drag ended.
    private func stopWaitingToStack() {
        pendingStack?.task.cancel()
        pendingStack = nil
        if stackTargetID != nil {
            withAnimation(Theme.Motion.settle) { stackTargetID = nil }
        }
    }

    // MARK: Turning the page

    /// Turns the page after the finger has held the item at a side of the
    /// screen for `edgeDelay`, and again after each turn while it stays there.
    /// Past the last page a new one opens, as on iPadOS.
    private func watchEdges() {
        guard let screen, !isTurningPage else { return }
        let margin = screen.gridOrigin.x
        let step = location.x < margin ? -1 : (location.x > screen.width - margin ? 1 : 0)
        let page = screen.page + step
        let opensPage = step == 1 && page == screen.pages.count && lastPageHoldsMore
        guard step != 0, screen.pages.indices.contains(page) || opensPage else { return stopWatchingEdges() }
        guard edge?.step != step else { return }
        stopWatchingEdges()
        let task = Task { [weak self] in
            try? await Task.sleep(for: Self.edgeDelay)
            guard !Task.isCancelled else { return }
            await self?.turn(to: page)
        }
        edge = (step, task)
    }

    /// True when the last page shows more than the lifted item, so a new page past it makes sense.
    private var lastPageHoldsMore: Bool {
        guard let screen, let lift else { return false }
        return screen.pages.last?.tiles.contains { $0.tile.id != lift.tile.id } == true
    }

    private func turn(to page: Int) async {
        isTurningPage = true
        if let screen, let planner, page == screen.pages.count {
            screen.layouts.update(for: screen.memberID) { $0.appendPage() }
            addedPage = planner.pages.count
            self.planner = HomeReorderPlanner(pages: planner.pages + [[]], columns: planner.columns, rows: planner.rows)
            // Scroll once the new page is drawn.
            var waited = 0
            while (self.screen?.pages.count ?? 0) <= page, waited < 10 {
                try? await Task.sleep(for: .milliseconds(20))
                waited += 1
            }
        }
        screen?.showPage(page, true)
        try? await Task.sleep(for: Self.pageTurn)
        isTurningPage = false
        edge = nil
        guard isLifted else { return }
        retarget()
        watchEdges()
    }

    private func stopWatchingEdges() {
        guard !isTurningPage else { return }
        edge?.task.cancel()
        edge = nil
    }
}
