import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center's tiles packed into a grid of four columns, or six or
/// eight when a tall list would not fit the screen's height (landscape). In
/// edit mode tiles hold still with pulsing outlines and show a remove badge,
/// as on iPadOS (`editPulse`). A short press lifts a tile
/// and it follows the finger while the others move aside at once to open the
/// slot it would land in, as on iPadOS (`ControlCenterReorder`).
struct ControlCenterGrid: View {
    let store: ControlCenterStore
    let isEditing: Bool
    var columns = 4
    /// True while a tile is lifted, so the panel stops scrolling: its pan
    /// took the drag over halfway and left the tile stranded.
    @Binding var isReordering: Bool
    /// The live order while a tile is dragged, nil otherwise.
    @State private var reorder: ControlCenterReorder?
    /// True while a reorder gesture runs. It resets on a cancel too, which
    /// `onEnded` never hears about, so the drag always ends (`endDrag`).
    @GestureState private var isDragging = false
    /// The dragged tile's frame when it was lifted, and how far the finger has moved since.
    @State private var lift: (frame: CGRect, translation: CGSize)?

    private static let space = "ControlCenterGrid"

    /// Square cells, `Theme.Spacing.m` apart.
    static let geometry = GridGeometry(cellSize: CGSize(width: 112, height: 112), spacing: Theme.Spacing.m)

    static func width(columns: Int) -> CGFloat {
        geometry.width(columns: columns)
    }

    /// The fewest columns (four, six or eight) whose packed grid fits `size`.
    /// Even counts keep two-column tiles aligned. Falls back to the widest
    /// grid that fits the width, which then scrolls.
    static func columns(for spans: [GridSpan], fitting size: CGSize) -> Int {
        let choices = [4, 6, 8].filter { $0 == 4 || width(columns: $0) <= size.width }
        for columns in choices
        where geometry.height(rows: GridPacker.rowCount(GridPacker.pack(spans, columns: columns))) <= size.height {
            return columns
        }
        return choices.last ?? 4
    }

    var body: some View {
        let ids = reorder?.order ?? store.visibleIDs
        let placements = GridPacker.pack(ids.map(store.span(for:)), columns: columns)
        let frames = Self.frames(ids: ids, placements: placements)
        ZStack(alignment: .topLeading) {
            ForEach(ids, id: \.self) { id in
                let frame = frames[id] ?? .zero
                let isLifted = reorder?.draggedID == id
                let shown = isLifted ? liftedFrame(at: frame) : frame
                tile(id, frame: frame, isLifted: isLifted)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: shown.minX, y: shown.minY)
                    .zIndex(isLifted ? 1 : 0)
            }
        }
        .frame(width: Self.width(columns: columns), height: Self.geometry.height(rows: GridPacker.rowCount(placements)),
               alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(Theme.Motion.settle, value: ids)
        .onChange(of: isEditing) { _, editing in
            if !editing { endDrag() }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { endDrag() }
        }
    }

    @ViewBuilder
    private func tile(_ id: String, frame: CGRect, isLifted: Bool) -> some View {
        if isEditing {
            ControlCenterTileView(tileID: id)
                .allowsHitTesting(false)
                .overlay(alignment: .topLeading) {
                    if !isLifted {
                        RemoveBadge("Remove \(store.title(for: id))") {
                            store.update { $0.remove(id) }
                        }
                        .offset(x: -8, y: -8)
                    }
                }
                .scaleEffect(isLifted ? 1.06 : 1)
                .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: 16, y: 8)
                .animation(Theme.Motion.settle, value: isLifted)
                // Still, with its outline pulsing, as Control Center edits on
                // iPadOS. A jiggle made glass tiles turn to frosted material.
                .editPulse(true)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                // A tap on a tile does nothing in edit mode. Without this it reached
                // the panel, which ends edit mode on a tap outside the tiles.
                .onTapGesture {}
                .gesture(reorderGesture(id, frame: frame))
                .accessibilityAction(named: "Move Earlier") { nudge(id, by: -1) }
                .accessibilityAction(named: "Move Later") { nudge(id, by: 1) }
        } else {
            ControlCenterTileView(tileID: id)
        }
    }

    /// Where the lifted tile is drawn: where it was lifted, moved with the finger.
    private func liftedFrame(at slot: CGRect) -> CGRect {
        guard let lift else { return slot }
        return lift.frame.offsetBy(dx: lift.translation.width, dy: lift.translation.height)
    }

    /// A short press lifts the tile (a quick swipe still scrolls), then it follows
    /// the finger. The same press lifts items on the Home Screen.
    private func reorderGesture(_ id: String, frame: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: HomeReorderSession.liftDelay)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($isDragging) { value, dragging, _ in
                if case .second(true, _) = value { dragging = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if reorder == nil {
                    reorder = ControlCenterReorder(draggedID: id, order: store.visibleIDs)
                    lift = (frame, .zero)
                    isReordering = true
                }
                guard let drag else { return }
                lift?.translation = drag.translation
                follow(drag.translation)
            }
            .onEnded { value in
                // A quick flick reports where it ended only here.
                if case .second(true, let drag?) = value { follow(drag.translation) }
                endDrag()
            }
    }

    /// Reorders for where the lifted tile's center now is.
    private func follow(_ translation: CGSize) {
        guard var next = reorder, let lift else { return }
        let center = CGPoint(x: lift.frame.midX + translation.width, y: lift.frame.midY + translation.height)
        let layout = { (ids: [String]) in
            Self.frames(ids: ids, placements: GridPacker.pack(ids.map(store.span(for:)), columns: columns))
        }
        if next.update(at: center, layout: layout) { reorder = next }
    }

    /// Saves the order the drag left and lets the tile settle into its slot.
    private func endDrag() {
        isReordering = false
        guard let reorder else { return }
        store.update { $0.reorder(visible: reorder.order) }
        withAnimation(Theme.Motion.settle) {
            self.reorder = nil
            lift = nil
        }
    }

    /// VoiceOver's way to reorder: one place earlier or later.
    private func nudge(_ id: String, by step: Int) {
        var order = store.visibleIDs
        guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return }
        order.swapAt(index, index + step)
        store.update { $0.reorder(visible: order) }
    }

    /// Each tile's frame, from the placements of `ids` in order.
    private static func frames(ids: [String], placements: [GridPlacement]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: placements.map { (ids[$0.index], geometry.frame(for: $0)) })
    }
}
