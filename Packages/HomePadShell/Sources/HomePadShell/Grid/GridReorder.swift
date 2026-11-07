import CoreGraphics

/// Where a dragged item lands in a grid that `GridPacker` lays out, so the
/// other items can open a slot for it while it moves, the way the iPadOS Home
/// Screen does. Generic over spans: the Home Screen uses it
/// (`HomeReorderPlanner`), and any grid packed the same way can.
///
/// The other items keep their order for the whole drag and only the dragged
/// one moves through it, so each place in that order gives one fixed slot.
/// The target is the slot nearest the dragged item, so it depends on where the
/// item is and on nothing else: taking a slot never moves the other slots, and
/// an icon and a widget of different sizes cannot trade places back and forth.
/// A margin keeps the current slot until another one is clearly nearer, so an
/// item resting on the line between two slots does not flicker.
struct GridReorder {
    /// One place the dragged item can take.
    struct Slot: Equatable {
        /// Where the item goes in the order of the others: 0 is first, `others.count` last.
        var index: Int
        /// The page it lands on, when the items fill more than one.
        var page: Int
        var placement: GridPlacement
    }

    /// The other items in order, without the dragged one.
    let others: [GridSpan]
    let dragged: GridSpan
    let columns: Int
    let rows: Int

    /// Every slot, one for each place in the order.
    func slots() -> [Slot] {
        (0...others.count).compactMap(slot(at:))
    }

    /// The slot the item takes at one place in the order.
    func slot(at index: Int) -> Slot? {
        guard (0...others.count).contains(index) else { return nil }
        var spans = others
        spans.insert(dragged, at: index)
        let pages = GridPacker.paginate(spans, columns: columns, rows: rows)
        for (page, placements) in pages.enumerated() {
            if let placement = placements.first(where: { $0.index == index }) {
                return Slot(index: index, page: page, placement: placement)
            }
        }
        return nil
    }

    /// The place in the order whose slot on `page` is nearest `center`, or nil
    /// when no slot lands on that page.
    ///
    /// - Parameters:
    ///   - center: The dragged item's center, in the space `frame` returns.
    ///   - page: Only slots on this page count.
    ///   - current: The place the item holds now. It stays unless another
    ///     slot's center is nearer by more than `hysteresis`.
    ///   - hysteresis: In points.
    ///   - frame: A placement's frame on its page.
    func target(
        for center: CGPoint, onPage page: Int, current: Int?, hysteresis: CGFloat,
        frame: (GridPlacement) -> CGRect
    ) -> Int? {
        let candidates = slots().filter { $0.page == page }.map { slot in
            let rect = frame(slot.placement)
            return (index: slot.index, distance: hypot(rect.midX - center.x, rect.midY - center.y))
        }
        // The first of equally near slots, so the same position always gives the same place.
        guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        if let held = candidates.first(where: { $0.index == current }), held.distance <= best.distance + hysteresis {
            return held.index
        }
        return best.index
    }
}
