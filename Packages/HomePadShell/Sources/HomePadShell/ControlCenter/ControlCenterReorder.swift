import CoreGraphics

/// The live order while a Control Center tile is dragged in edit mode, as on
/// iPadOS: the tile follows the finger and the others move aside at once to
/// open the slot it would land in, before anything is dropped.
struct ControlCenterReorder: Equatable {
    let draggedID: String
    /// Every tile in order, the dragged one at the slot it would land in.
    private(set) var order: [String]

    init(draggedID: String, order: [String]) {
        self.draggedID = draggedID
        self.order = order
    }

    /// Moves the dragged tile into the slot of the tile under `point` (the
    /// dragged tile's center, which is what the eye follows), or to the end
    /// when the point is below every tile. `layout` gives each tile's frame for
    /// an order. Returns true when the order changed.
    ///
    /// A move that would leave the same tile under the point is skipped: with
    /// tiles of different sizes it flipped back on the next update. No other
    /// memory is kept, so going back over a tile always moves it back. (Holding
    /// the last tile traded with until the finger left it stopped tiles from
    /// moving back when the dragged one returned to where it started.)
    mutating func update(at point: CGPoint, layout: ([String]) -> [String: CGRect]) -> Bool {
        let frames = layout(order)
        guard let from = order.firstIndex(of: draggedID) else { return false }
        if let target = frames.first(where: { $0.key != draggedID && $0.value.contains(point) })?.key,
           let to = order.firstIndex(of: target) {
            var trial = order
            trial.remove(at: from)
            trial.insert(draggedID, at: to)
            guard layout(trial)[target]?.contains(point) != true else { return false }
            order = trial
            return true
        }
        let bottom = frames.values.map(\.maxY).max() ?? 0
        guard point.y > bottom, from != order.count - 1 else { return false }
        order.remove(at: from)
        order.append(draggedID)
        return true
    }
}
