import HomePadCore
import SwiftUI

/// A capsule Liquid Glass button with a symbol and a title, sized for reading
/// across a room: "Start Cooking", "+1 min", "Not Now", "Edit". It is drawn
/// the same way as `GlassIconButton`, and its heights match the round sizes,
/// so the two sit side by side in headers and control rows.
///
/// In a header it takes the toolbar size (`Theme.Size.toolbarItem`, headline
/// text), shows only its symbol when the toolbar is short of room, and moves
/// into the More menu when even that does not fit.
///
///     GlassCapsuleButton("Ingredients", systemImage: "checklist") { showIngredients() }
///     GlassCapsuleButton("Stop", systemImage: "stop.fill", isProminent: true, tint: .orange) { stop() }
public struct GlassCapsuleButton: View {
    private let title: String
    private let systemImage: String?
    private let size: GlassCapsuleButtonStyle.Size?
    private let isProminent: Bool
    private let tint: Color?
    private let action: () -> Void
    @Environment(\.appAccent) private var appAccent
    @Environment(\.toolbarPlacement) private var placement

    /// - Parameters:
    ///   - title: The button title.
    ///   - systemImage: Optional SF Symbol before the title. In a header it stands
    ///     in for the title when the toolbar is short of room.
    ///   - size: Text size and height. `.large` when nil, and `.toolbar` in a header.
    ///   - isProminent: Fills the glass for the screen's one primary action.
    ///   - tint: Fill color of a prominent button. The app's accent when nil.
    ///   - action: Called on tap.
    public init(
        _ title: String, systemImage: String? = nil, size: GlassCapsuleButtonStyle.Size? = nil,
        isProminent: Bool = false, tint: Color? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.isProminent = isProminent
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Group {
            if placement.isToolbar, let systemImage, !placement.showsTitles {
                Button(action: action) { Label(title, systemImage: systemImage) }
                    .buttonStyle(.glassIcon(tint: fill))
            } else if placement.isToolbar {
                Button(action: action) {
                    if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                }
                .buttonStyle(.glassCapsule(size: size, tint: fill))
            } else {
                Button(action: action) {
                    HStack(spacing: Theme.Spacing.s) {
                        if let systemImage { Image(systemName: systemImage) }
                        Text(title)
                    }
                }
                .buttonStyle(.glassCapsule(size: size, tint: fill))
            }
        }
        .modifier(ToolbarItemVisibility(isProminent: fill != nil))
    }

    private var fill: Color? {
        isProminent ? (tint ?? appAccent) : nil
    }
}

/// The style behind `GlassCapsuleButton`, for `Menu` labels, `ShareLink`
/// and other buttons that are not plain `Button`s.
///
///     Menu { ... } label: { Label("Everyone", systemImage: "person.crop.circle") }
///         .buttonStyle(.glassCapsule())
public struct GlassCapsuleButtonStyle: ButtonStyle {
    /// Text size and height of a capsule button.
    public enum Size: Sendable {
        /// Headline text, `Theme.Size.minTapTarget` tall, for bars and rows.
        case regular
        /// Title 3 text, `Theme.Size.tapTarget` tall, the default outside headers. Matches `tapTarget` round buttons.
        case large
        /// Title 2 text, `Theme.Size.roundControl` tall, for the main actions of a full-screen alert.
        case extraLarge
        /// Headline text, `Theme.Size.toolbarItem` tall, for header toolbars. Headers pick it for you.
        case toolbar

        var font: Font {
            switch self {
            case .regular, .toolbar: .headline
            case .large: .title3.weight(.semibold)
            case .extraLarge: .title2.weight(.semibold)
            }
        }

        var height: CGFloat {
            switch self {
            case .regular: Theme.Size.minTapTarget
            case .large: Theme.Size.tapTarget
            case .extraLarge: Theme.Size.roundControl
            case .toolbar: Theme.Size.toolbarItem
            }
        }
    }

    let size: Size?
    let tint: Color?

    /// - Parameters:
    ///   - size: Text size and height. `.large` when nil, and always `.toolbar` in a header.
    ///   - tint: Fills the glass with a color for the primary action. Nil is plain glass.
    public init(size: Size? = nil, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassCapsuleLabel(configuration: configuration, size: size, tint: tint)
    }
}

public extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    /// A capsule Liquid Glass button. See `GlassCapsuleButton`.
    static func glassCapsule(size: GlassCapsuleButtonStyle.Size? = nil, tint: Color? = nil) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(size: size, tint: tint)
    }
}

private struct GlassCapsuleLabel: View {
    let configuration: ButtonStyleConfiguration
    let size: GlassCapsuleButtonStyle.Size?
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayCondition) private var condition
    @Environment(\.toolbarPlacement) private var placement
    @Environment(\.isInToolbarGroup) private var isInGroup
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = resolvedSize
        let label = configuration.label
            .font(size.font)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: size == .toolbar ? ToolbarMetrics.maxTitleWidth : nil)
            .fixedSize(horizontal: size == .toolbar, vertical: false)
            .foregroundStyle(textColor)
            .padding(.horizontal, padding(size))
            .frame(minWidth: size == .toolbar ? size.height : nil, minHeight: size.height)
            .contentShape(Capsule())
        if isInGroup {
            label
                .background(Color.primary.opacity(configuration.isPressed ? 0.18 : 0), in: Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.Motion.standard, value: configuration.isPressed)
        } else {
            label
                .glassEffect((fill.map { Glass.regular.tint($0) } ?? .regular).interactive(), in: Capsule())
                .editPulseBorder(in: Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.Motion.standard, value: configuration.isPressed)
        }
    }

    private var resolvedSize: GlassCapsuleButtonStyle.Size {
        placement.isToolbar || isInGroup ? .toolbar : (size ?? .large)
    }

    private func padding(_ size: GlassCapsuleButtonStyle.Size) -> CGFloat {
        switch size {
        case .regular, .toolbar: isInGroup ? Theme.Spacing.s : Theme.Spacing.m
        case .large, .extraLarge: Theme.Spacing.l
        }
    }

    /// Night mode tints everything red, so a filled button would hide its title.
    private var fill: Color? {
        condition == .night ? nil : tint
    }

    private var textColor: AnyShapeStyle {
        guard let fill else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(Color.foreground(on: fill, in: colorScheme))
    }
}

public extension View {
    /// `.glassProminent` (tinted) for the primary action and `.glass` otherwise,
    /// chosen at runtime without duplicating the button. Use it for system
    /// sized buttons. Use `GlassCapsuleButton` for big labeled actions.
    ///
    ///     Button("Text") { mode = .text }.glassButtonStyle(isProminent: mode == .text)
    ///
    /// - Parameters:
    ///   - isProminent: Use the prominent style.
    ///   - tint: Fill color of the prominent style. The accent color when nil.
    @ViewBuilder
    func glassButtonStyle(isProminent: Bool, tint: Color? = nil) -> some View {
        if isProminent {
            buttonStyle(.glassProminent).tint(tint)
        } else {
            buttonStyle(.glass)
        }
    }
}
