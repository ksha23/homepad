import HomePadCore
import HomePadUI
import SwiftUI

/// One page of the Home Screen grid. Long-press on empty space enters edit
/// mode, and a tap there ends it, as on iPadOS. While an item is lifted in edit mode its slot stays open here and
/// the item is drawn at the finger (`HomeReorderLiftedTile`).
struct HomeScreenPageView: View {
    let page: RenderedHomePage
    let metrics: HomeGridMetrics
    let memberID: HouseholdMember.ID?
    /// The item lifted to be moved, if any.
    var liftedID: String?
    /// The widget the lifted one would join as a stack, drawn a little larger.
    var stackTargetID: String?
    /// Opens Edit Widget for a widget on the page.
    var onEditWidget: (HomeWidgetEditRequest) -> Void = { _ in }
    @Environment(ShellNavigator.self) private var navigator
    @Environment(HomeScreenLayoutStore.self) private var layouts

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if navigator.isEditingHomeScreen { endEditing() } }
                .onLongPressGesture(minimumDuration: HomeTileView.editHold) { navigator.isEditingHomeScreen = true }
            // Keyed by item, so items slide to their new slots instead of swapping contents.
            ForEach(page.tiles, id: \.tile.id) { entry in
                let frame = metrics.frame(for: entry.placement)
                // The tile without the name under it, so the preview in Edit Widget matches it.
                let tile = CGSize(width: frame.width, height: frame.height - metrics.widgetLabelHeight)
                HomeTileView(tile: entry.tile, metrics: metrics, memberID: memberID, onNudge: { nudge(entry.tile.id, by: $0) },
                             onEditWidget: { onEditWidget(HomeWidgetEditRequest(id: entry.tile.id, tile: tile)) })
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .scaleEffect(entry.tile.id == stackTargetID ? HomeReorderSession.stackTargetScale : 1)
                    .opacity(entry.tile.id == liftedID ? 0 : 1)
            }
        }
    }

    /// The same as Done: empty pages go with edit mode.
    private func endEditing() {
        layouts.update(for: memberID) { $0.removeEmptyPages() }
        navigator.isEditingHomeScreen = false
    }

    /// Moves an item one place earlier or later on this page.
    private func nudge(_ id: String, by step: Int) {
        let ids = page.tiles.map(\.tile.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + step) else { return }
        let other = ids[index + step]
        withAnimation(Theme.Motion.settle) {
            layouts.update(for: memberID) { step < 0 ? $0.move(id, before: other) : $0.move(other, before: id) }
        }
    }
}
