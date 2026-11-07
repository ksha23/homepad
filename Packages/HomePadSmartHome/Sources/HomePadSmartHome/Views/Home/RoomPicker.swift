import HomePadCore
import HomePadUI
import SwiftUI

/// Capsules for "All Rooms" and each room, one selected, scrolling sideways
/// when they do not fit. Like `ChoiceChips`, drawn as large `glassCapsule`
/// buttons, as tall as the status chips and the Scenes button beside them. The chips stay inside the picker's frame and fade out at an
/// edge with more rooms past it, since the picker sits between other things.
struct RoomPicker: View {
    @Environment(\.displayCondition) private var condition
    let rooms: [String]
    @Binding var selection: String?
    @State private var hiddenEdges = HiddenEdges()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    chip(for: nil, title: "All Rooms")
                    ForEach(rooms, id: \.self) { chip(for: $0, title: $0) }
                }
            }
            .onScrollGeometryChange(for: HiddenEdges.self, of: { HiddenEdges($0) }, action: { _, edges in hiddenEdges = edges })
            // The picked room scrolls toward the middle, clear of the faded
            // edges: one opened at launch, or one tapped at an edge.
            .onChange(of: selection, initial: true) { _, room in
                withAnimation(Theme.Motion.standard) { proxy.scrollTo(room ?? Self.allRoomsID, anchor: .center) }
            }
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [hiddenEdges.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Theme.Spacing.l)
                Color.black
                LinearGradient(colors: [.black, hiddenEdges.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Theme.Spacing.l)
            }
            .animation(Theme.Motion.standard, value: hiddenEdges)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// Which ends have chips scrolled out of sight. Only those ends fade, so a
    /// chip that is fully in view is never dimmed.
    private struct HiddenEdges: Equatable {
        var leading = false
        var trailing = false

        init() {}

        init(_ geometry: ScrollGeometry) {
            let offset = geometry.contentOffset.x + geometry.contentInsets.leading
            let overflow = geometry.contentSize.width + geometry.contentInsets.leading + geometry.contentInsets.trailing
                - geometry.containerSize.width
            leading = offset > 1
            trailing = offset < overflow - 1
        }
    }

    /// The scroll ID of "All Rooms". Rooms use their names.
    private static let allRoomsID = "\u{0}all"

    private func chip(for room: String?, title: String) -> some View {
        let isSelected = room == selection
        return Button {
            selection = room
        } label: {
            // Night mode draws no fill, so the other rooms dim instead. Glass
            // draws its text vibrant and ignores opacity, so this is a style.
            if condition == .night && !isSelected {
                Text(title).foregroundStyle(.secondary)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.glassCapsule(size: .large, tint: isSelected ? .accentColor : nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(room ?? Self.allRoomsID)
    }
}
