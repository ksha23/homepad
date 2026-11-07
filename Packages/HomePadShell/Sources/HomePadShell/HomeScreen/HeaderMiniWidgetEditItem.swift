import HomePadCore
import HomePadUI
import SwiftUI

/// The header's mini widget in Home Screen edit mode, first in the edit bar,
/// where the header's lines were: it jiggles with the icons and widgets, its
/// minus badge removes it, and the size button beside it steps through its
/// sizes, as a widget's does. Once removed, the edit bar offers to add one
/// in its place.
struct HeaderMiniWidgetEditItem: View {
    let widget: MiniWidgetDescriptor
    let placement: MiniWidgetPlacement
    let textSize: CGFloat
    let onChange: (MiniWidgetPlacement?) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            widget.makeView(MiniWidgetContext(size: widget.shownSize(placement.size), surface: .wallpaper,
                                              textSize: textSize, keepsSomething: true))
                // Room for the minus badge on its corner, as on a widget.
                .padding(Theme.Spacing.m)
                .overlay(alignment: .topLeading) {
                    RemoveBadge("Remove \(widget.title)") { change(to: nil) }
                        .offset(x: -10, y: -10)
                }
                .jiggle(true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(widget.title)
            if widget.supportedSizes.count > 1 {
                GlassIconButton("arrow.up.left.and.arrow.down.right", label: "Change size of \(widget.title)",
                                size: Theme.Size.minTapTarget) {
                    var resized = placement
                    resized.size = widget.size(after: widget.shownSize(placement.size))
                    change(to: resized)
                }
                .accessibilityValue(widget.shownSize(placement.size).title)
            }
        }
    }

    private func change(to changed: MiniWidgetPlacement?) {
        withAnimation(Theme.Motion.settle) { onChange(changed) }
    }
}
