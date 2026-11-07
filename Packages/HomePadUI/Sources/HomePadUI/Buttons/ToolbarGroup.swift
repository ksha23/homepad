import SwiftUI

/// Related header items in one glass capsule, like an iPadOS toolbar group:
/// previous, Today and next in Calendar. The items drop their own glass, icon
/// items narrow a little, and a press lights the item under the finger.
///
///     ToolbarGroup {
///         GlassIconButton("chevron.left", label: "Previous") { step(-1) }
///         GlassCapsuleButton("Today") { showToday() }
///         GlassIconButton("chevron.right", label: "Next") { step(1) }
///     }
///
/// In the More menu the group's items become one section. Set
/// `toolbarItemPriority` on the group, not on the items inside it. A
/// prominent action never goes in a group.
public struct ToolbarGroup<Content: View>: View {
    @Environment(\.toolbarPlacement) private var placement
    private let content: Content

    /// - Parameter content: The items, without a stack around them.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Group {
            if placement.isMenu {
                Section { content }
            } else {
                HStack(spacing: 0) { content }
                    .padding(.horizontal, Theme.Spacing.xs)
                    .environment(\.isInToolbarGroup, true)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .modifier(ToolbarItemVisibility(isProminent: false))
    }
}
