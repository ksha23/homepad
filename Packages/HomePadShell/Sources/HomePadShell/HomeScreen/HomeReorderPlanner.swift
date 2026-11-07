import CoreGraphics
import HomePadCore

/// Plans a live reorder on the Home Screen: where a dragged item lands as it
/// moves over the page on screen (`GridReorder`), and which widget it would
/// join as a stack. Pure, so tests drive it without views.
/// `HomeReorderSession` keeps one for each drag.
///
/// Pages are logical (`HomeScreenLayout.pages`), and one that holds more than
/// fits continues on the next page drawn. So a drawn page is a part of a
/// logical page, and the item can land on any part of any logical page.
struct HomeReorderPlanner {
    /// An item as the Home Screen draws it.
    struct Item: Equatable {
        var id: String
        var span: GridSpan
        /// How many widgets it stands for when it can join a stack: one for a
        /// widget, its count for a stack, nil for an app.
        var stackCount: Int? = nil
    }

    /// Where the dragged item goes: before an item on a logical page, or at
    /// that page's end. `HomeScreenLayout.move(_:toPage:before:)` applies it.
    struct Target: Equatable {
        var page: Int
        var beforeID: String?
    }

    /// A drawn page: which logical page it shows, and which of its parts.
    struct DrawnPage: Equatable {
        var page: Int
        var part: Int
    }

    /// The saved layout as drawn: each logical page's items that show, in order.
    let pages: [[Item]]
    let columns: Int
    let rows: Int

    /// The target that leaves the item where it is.
    func origin(of itemID: String) -> Target? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                return Target(page: page, beforeID: items.indices.contains(index + 1) ? items[index + 1].id : nil)
            }
        }
        return nil
    }

    /// The pages with the item moved to a target, as the Home Screen would draw them.
    func moving(_ itemID: String, to target: Target) -> [[Item]] {
        guard let item = pages.joined().first(where: { $0.id == itemID }), pages.indices.contains(target.page) else {
            return pages
        }
        var moved = pages.map { $0.filter { $0.id != itemID } }
        let index = target.beforeID.flatMap { id in moved[target.page].firstIndex { $0.id == id } } ?? moved[target.page].count
        moved[target.page].insert(item, at: index)
        return moved
    }

    /// The drawn pages for these pages, in order, packed as `HomeScreenPages.render` packs them.
    func drawnPages(_ pages: [[Item]]) -> [DrawnPage] {
        pages.enumerated().flatMap { page, items in
            GridPacker.paginate(items.map(\.span), columns: columns, rows: rows).indices.map { DrawnPage(page: page, part: $0) }
        }
    }

    /// Where the item lands for its center at `center` (in the grid's space) while drawn page
    /// `drawn` is on screen. Only slots on that page count, so the item never jumps off screen.
    ///
    /// - Parameters:
    ///   - current: The target the item holds now. The pages are drawn with it.
    ///   - hysteresis: How much nearer another slot must be before the item leaves its slot.
    ///   - frame: A placement's frame on its page.
    func target(
        moving itemID: String, center: CGPoint, onDrawnPage drawn: Int, current: Target,
        hysteresis: CGFloat, frame: (GridPlacement) -> CGRect
    ) -> Target {
        guard let item = pages.joined().first(where: { $0.id == itemID }) else { return current }
        let shown = drawnPages(moving(itemID, to: current))
        guard shown.indices.contains(drawn) else { return current }
        let page = shown[drawn].page
        let others = pages[page].filter { $0.id != itemID }
        let reorder = GridReorder(others: others.map(\.span), dragged: item.span, columns: columns, rows: rows)
        let held = current.page == page ? place(of: current, in: others) : nil
        guard let index = reorder.target(
            for: center, onPage: shown[drawn].part, current: held, hysteresis: hysteresis, frame: frame
        ) else { return current }
        return Target(page: page, beforeID: others.indices.contains(index) ? others[index].id : nil)
    }

    /// Where the item sits while it is at `target`: the index of its drawn page and its placement there.
    func slot(of itemID: String, at target: Target) -> (page: Int, placement: GridPlacement)? {
        var drawn = 0
        for items in moving(itemID, to: target) {
            for part in GridPacker.paginate(items.map(\.span), columns: columns, rows: rows) {
                if let placement = part.first(where: { items[$0.index].id == itemID }) { return (drawn, placement) }
                drawn += 1
            }
        }
        return nil
    }

    /// The index of a drawn page once the item is at `target`, or nil when there is no such page.
    func index(of drawn: DrawnPage, moving itemID: String, to target: Target) -> Int? {
        drawnPages(moving(itemID, to: target)).firstIndex(of: drawn)
    }

    /// Which logical page and part a drawn page shows while the item is at `target`.
    func drawnPage(at index: Int, moving itemID: String, to target: Target) -> DrawnPage? {
        let shown = drawnPages(moving(itemID, to: target))
        return shown.indices.contains(index) ? shown[index] : nil
    }

    // MARK: Stacking

    /// The item the dragged one would join as a stack, as dropping a widget
    /// on another does on iPadOS: the widget or stack under `center` on drawn
    /// page `drawn`, of the dragged item's size, with room for all their
    /// widgets. Nil when there is none, or when the dragged item is an app.
    ///
    /// - Parameters:
    ///   - current: The target the item holds now. The pages are drawn with it.
    ///   - frame: A placement's frame on its page.
    func stackTarget(
        moving itemID: String, center: CGPoint, onDrawnPage drawn: Int, current: Target,
        frame: (GridPlacement) -> CGRect
    ) -> String? {
        guard let dragged = pages.joined().first(where: { $0.id == itemID }), let count = dragged.stackCount else { return nil }
        var index = 0
        for items in moving(itemID, to: current) {
            for part in GridPacker.paginate(items.map(\.span), columns: columns, rows: rows) {
                defer { index += 1 }
                guard index == drawn else { continue }
                let under = part.first { placement in
                    let other = items[placement.index]
                    guard other.id != itemID, other.span == dragged.span, let otherCount = other.stackCount,
                          count + otherCount <= WidgetStack.maxMembers else { return false }
                    return frame(placement).contains(center)
                }
                return under.map { items[$0.index].id }
            }
        }
        return nil
    }

    /// The planner once the dragged item has joined `targetID` as a stack:
    /// the dragged item gone and the target under the stack's ID, for where it settles.
    func stacking(_ itemID: String, onto targetID: String, as stackID: String) -> HomeReorderPlanner {
        let count = pages.joined().filter { $0.id == itemID || $0.id == targetID }.compactMap(\.stackCount).reduce(0, +)
        let merged = pages.map { items in
            items.compactMap { item -> Item? in
                if item.id == itemID { return nil }
                if item.id == targetID { return Item(id: stackID, span: item.span, stackCount: count) }
                return item
            }
        }
        return HomeReorderPlanner(pages: merged, columns: columns, rows: rows)
    }

    /// The target's place in the order of the other items.
    private func place(of target: Target, in others: [Item]) -> Int {
        target.beforeID.flatMap { id in others.firstIndex { $0.id == id } } ?? others.count
    }
}
