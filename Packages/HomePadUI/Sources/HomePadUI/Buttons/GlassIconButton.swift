import HomePadCore
import SwiftUI

/// A round Liquid Glass button with one SF Symbol: close, add, play, talk,
/// previous and next. It is the one round icon button in HomePad, so headers,
/// banners, camera screens and media controls all match.
///
/// Pick the size from the curated tokens:
///
/// | Size | Use |
/// |---|---|
/// | `Theme.Size.minTapTarget` | Inside dense rows and chips |
/// | `Theme.Size.toolbarItem` | Header toolbars and close. Headers pick it for you |
/// | `Theme.Size.tapTarget` (default) | Banners and controls on a screen |
/// | `Theme.Size.roundControl` | Secondary transport (previous, next, step back) |
/// | `Theme.Size.heroControl` | The main control of a screen (play, shutter, answer) |
///
/// In a header (`AppHeader`, `DetailHeader`) it takes the toolbar size whatever
/// size it was given, loses its own glass inside a `ToolbarGroup`, and moves
/// into the More menu when the toolbar runs out of room.
///
/// `isProminent` fills the glass with the app's accent (`\.appAccent`) for the
/// screen's primary action, and `tint` fills it with another color. The symbol
/// turns black on light fills (white, yellow, `.primary` in Dark) and white on
/// the rest (`Color.foreground(on:in:)`). In night mode the fill drops away, so
/// the red tint never hides the symbol. Plain glass draws the symbol in
/// `.primary`, which follows the appearance and the glass.
///
///     GlassIconButton("plus", label: "Add City", isProminent: true) { isAdding = true }
///     GlassIconButton("play.fill", label: "Play", size: Theme.Size.heroControl, tint: .white) { play() }
public struct GlassIconButton: View {
    private let systemImage: String
    private let label: String
    private let size: CGFloat?
    private let isProminent: Bool
    private let tint: Color?
    private let foreground: Color?
    private let action: () -> Void
    @Environment(\.appAccent) private var appAccent

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - label: What VoiceOver reads, and the item's title in a More menu.
    ///   - size: Diameter in points. Use a `Theme.Size` token. `tapTarget` when nil.
    ///   - isProminent: Fills the glass with the app's accent for the primary action.
    ///   - tint: Fills the glass with this color instead. Nil is plain glass.
    ///   - foreground: Overrides the symbol color.
    ///   - action: Called on tap.
    public init(
        _ systemImage: String, label: String, size: CGFloat? = nil, isProminent: Bool = false,
        tint: Color? = nil, foreground: Color? = nil, action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.size = size
        self.isProminent = isProminent
        self.tint = tint
        self.foreground = foreground
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
        }
        .buttonStyle(.glassIcon(size: size, tint: fill, foreground: foreground))
        .accessibilityLabel(label)
        .modifier(ToolbarItemVisibility(isProminent: fill != nil))
    }

    private var fill: Color? {
        tint ?? (isProminent ? appAccent : nil)
    }
}

/// The style behind `GlassIconButton`, for buttons that are not plain
/// `Button`s, such as `ShareLink`, `PhotosPicker` or a `Menu` label.
///
///     ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
///         .buttonStyle(.glassIcon())
public struct GlassIconButtonStyle: ButtonStyle {
    let size: CGFloat?
    let tint: Color?
    let foreground: Color?

    /// - Parameters:
    ///   - size: Diameter in points. Use a `Theme.Size` token. `tapTarget` when
    ///     nil, and always `toolbarItem` in a header.
    ///   - tint: Fills the glass with a color. Nil is plain glass.
    ///   - foreground: Overrides the symbol color.
    public init(size: CGFloat? = nil, tint: Color? = nil, foreground: Color? = nil) {
        self.size = size
        self.tint = tint
        self.foreground = foreground
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassIconLabel(configuration: configuration, size: size, tint: tint, foreground: foreground)
    }
}

public extension ButtonStyle where Self == GlassIconButtonStyle {
    /// A round Liquid Glass icon button. See `GlassIconButton`.
    static func glassIcon(size: CGFloat? = nil, tint: Color? = nil, foreground: Color? = nil) -> GlassIconButtonStyle {
        GlassIconButtonStyle(size: size, tint: tint, foreground: foreground)
    }
}

private struct GlassIconLabel: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat?
    let tint: Color?
    let foreground: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayCondition) private var condition
    @Environment(\.toolbarPlacement) private var placement
    @Environment(\.isInToolbarGroup) private var isInGroup
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isInGroup {
            grouped
        } else {
            round
        }
    }

    private var round: some View {
        let diameter = placement.isToolbar ? Theme.Size.toolbarItem : (size ?? Theme.Size.tapTarget)
        // Toolbar sized buttons outside a header (the shell's close button) match the header's symbols.
        let isToolbarSized = diameter == Theme.Size.toolbarItem
        return configuration.label
            .labelStyle(.iconOnly)
            .font(isToolbarSized ? ToolbarMetrics.symbolFont : .system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(symbolColor)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glassEffect(glass, in: Circle())
            .editPulseBorder(in: Circle())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }

    /// Inside a `ToolbarGroup` the group draws the glass. A press lights the item.
    private var grouped: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(ToolbarMetrics.symbolFont)
            .foregroundStyle(symbolColor)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: ToolbarMetrics.groupedIconWidth, height: Theme.Size.toolbarItem)
            .background(Color.primary.opacity(configuration.isPressed ? 0.18 : 0), in: Capsule())
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }

    /// Night mode tints everything red, so a filled button would hide its symbol.
    private var fill: Color? {
        condition == .night ? nil : tint
    }

    private var glass: Glass {
        (fill.map { Glass.regular.tint($0) } ?? .regular).interactive()
    }

    /// Plain glass keeps the primary style, so the symbol follows the glass
    /// when it turns light over a bright background (Mirror's ring light).
    private var symbolColor: AnyShapeStyle {
        guard condition != .night else { return AnyShapeStyle(.primary) }
        if let foreground { return AnyShapeStyle(foreground) }
        guard let fill else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(Color.foreground(on: fill, in: colorScheme))
    }
}
