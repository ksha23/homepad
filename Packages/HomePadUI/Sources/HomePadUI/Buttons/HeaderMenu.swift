import SwiftUI

/// A menu in a header toolbar: a round symbol, or a capsule with its title
/// that becomes the symbol when the toolbar is short of room. In the More
/// menu it becomes a submenu.
///
///     HeaderMenu("More", systemImage: "ellipsis") {
///         Button("Pin", systemImage: "pin") { pin() }
///     }
public struct HeaderMenu<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let showsTitle: Bool
    private let content: Content
    @Environment(\.toolbarPlacement) private var placement

    /// - Parameters:
    ///   - title: What VoiceOver reads, and the title shown when `showsTitle` is true.
    ///   - systemImage: SF Symbol name.
    ///   - showsTitle: Shows the title beside the symbol while there is room.
    ///   - content: The menu's items.
    public init(_ title: String, systemImage: String, showsTitle: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.showsTitle = showsTitle
        self.content = content()
    }

    public var body: some View {
        Group {
            if showsTitle && placement.showsTitles {
                menu.buttonStyle(.glassCapsule())
            } else {
                menu.buttonStyle(.glassIcon())
            }
        }
        .accessibilityLabel(title)
        .modifier(ToolbarItemVisibility(isProminent: false))
    }

    private var menu: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// A choice of what the screen shows, as a header menu: "Day", "Week" or
/// "Month" in Calendar, a clock style in World Clock. It sits next to the
/// title (`titleAccessory`) and shows the current choice with a chevron, or
/// only its symbol when the header is short of room.
///
///     HeaderPicker("View", selection: $mode, title: mode.title, systemImage: mode.systemImage) {
///         ForEach(CalendarDisplayMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
///     }
public struct HeaderPicker<Value: Hashable, Options: View>: View {
    private let label: String
    @Binding private var selection: Value
    private let title: String
    private let systemImage: String
    private let options: Options
    @Environment(\.toolbarPlacement) private var placement

    /// - Parameters:
    ///   - label: What the choice is about ("View"), read by VoiceOver.
    ///   - selection: The chosen value.
    ///   - title: The chosen value's name, shown in the header.
    ///   - systemImage: The chosen value's symbol, shown when the header is short of room.
    ///   - options: The choices, tagged with their values.
    public init(
        _ label: String, selection: Binding<Value>, title: String, systemImage: String,
        @ViewBuilder options: () -> Options
    ) {
        self.label = label
        self._selection = selection
        self.title = title
        self.systemImage = systemImage
        self.options = options()
    }

    public var body: some View {
        Group {
            if placement.showsTitles {
                menu {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(title)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.glassCapsule())
            } else {
                menu { Label(title, systemImage: systemImage) }
                    .buttonStyle(.glassIcon())
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(title)
        .sensoryFeedback(.selection, trigger: selection)
        .modifier(ToolbarItemVisibility(isProminent: false))
    }

    private func menu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Picker(self.label, selection: $selection) { options }
                .pickerStyle(.inline)
        } label: {
            label()
        }
    }
}
