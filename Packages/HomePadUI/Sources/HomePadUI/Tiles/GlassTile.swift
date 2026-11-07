import HomePadCore
import SwiftUI

/// The rounded glass tile used across faces, widgets and the Home app. It
/// fills its frame, so use it for grid cells. Use `GlassPanel` for floating
/// containers that hug their content. Several views inside stack vertically
/// on one tile.
///
///     GlassTile { WeatherSummary() }
///     GlassTile(isHighlighted: isOn, tint: .yellow) { LightLabel() }
///     GlassTile(surface: .solid) { UpNextList() }
public struct GlassTile<Content: View>: View {
    /// What the tile is drawn on.
    public enum Surface: Sendable {
        /// Liquid Glass over what is behind it: frosted diffusion blur with specular
        /// edges and light refraction via the system `glassEffect` API.
        case glass
        /// An opaque card, like HomeView's Calendar widget: white with dark
        /// text in the light appearance, black with light text in the dark
        /// one, and black at night either way, so the red night tint never
        /// turns it into a bright red block. For the Calendar, Reminders and
        /// Timers widgets.
        case solid
        /// Dual-layer Liquid Glass: a frosted material base to diffuse background noise,
        /// topped with crystal-clear Liquid Glass for mirror-like specular edges and fluid lens refraction.
        case dualLayerGlass
        /// Deprecated alias to .glass
        case liquidGlass
    }

    private let isHighlighted: Bool
    private let tint: Color?
    private let fill: Double
    private let surface: Surface
    private let content: Content
    @Environment(\.displayCondition) private var condition
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.backdropScheme) private var backdropScheme
    @Environment(\.isBackdropBlurred) private var isBackdropBlurred
    @Environment(\.glassBackdropTone) private var backdropTone

    /// - Parameters:
    ///   - isHighlighted: Fills the tile with `tint` instead of material, for an "on" state.
    ///   - tint: Fill color when highlighted. White when nil.
    ///   - fill: How much of the tile the highlight covers from the leading edge,
    ///     such as a light's brightness. Use `fillAwareForeground` for text that
    ///     crosses the edge.
    ///   - surface: Glass (the default) or an opaque card.
    ///   - content: The tile's content, padded by `Theme.Spacing.m`.
    public init(isHighlighted: Bool = false, tint: Color? = nil, fill: Double = 1, surface: Surface = .glass,
                @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.tint = tint
        self.fill = fill
        self.surface = surface
        self.content = content()
    }

    /// True for a solid card in the light appearance outside night: white, with
    /// the light color scheme so `.primary` and `.secondary` text turn dark.
    private var isLightCard: Bool { surface == .solid && condition != .night && colorScheme == .light }

    private var isDark: Bool {
        colorScheme == .dark || backdropScheme == .dark
    }

    /// A solid card sets its own scheme to match its color. Glass on a face
    /// or a wallpaper takes the backdrop's (`glassBackdrop(_:)`), so it is dark
    /// with light text over a dark backdrop and light with dark text over a
    /// bright one. Glass on a page keeps the app's.
    private var contentScheme: ColorScheme {
        guard surface == .solid else { return isDark ? .dark : (backdropScheme ?? colorScheme) }
        return isLightCard ? .light : .dark
    }

    /// How bright the tile's own surface is, for the fill of the controls in
    /// it (`controlSurface`). Glass is worked out from the backdrop under it
    /// (`GlassSurface`), or the page color when it sits on a page. Night keeps
    /// the dark glass over black that its red rows were made on.
    private var surfaceTone: BackdropTone {
        guard surface != .solid else { return contentScheme == .light ? .white : .black }
        let page: BackdropTone = colorScheme == .light ? .white : .black
        let backdrop: BackdropTone = condition == .night ? .black : backdropTone ?? page
        return GlassSurface.tone(over: backdrop, scheme: contentScheme, isBackdropBlurred: isBackdropBlurred)
    }

    public var body: some View {
        // One stack, so several views share one tile instead of each getting its own.
        let inner = VStack(alignment: .leading, spacing: Theme.Spacing.s) { content }
            .environment(\.controlCornerRadius, Theme.Radius.tileControl)
            // The content sits on the tile, not on the backdrop.
            .environment(\.tileSurfaceTone, surfaceTone)
            .environment(\.glassBackdropTone, nil)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .levelFill(isHighlighted ? fill : 0, tint: tint ?? .white, in: shape)

        switch surface {
        case .solid:
            inner
                .background {
                    shape.fill(isLightCard ? Color.white : Color.black)
                }
                .overlay {
                    shape.strokeBorder(contentScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.15), lineWidth: 1)
                }
                .editPulseBorder(in: shape)
                .nightModeAware()
                .environment(\.colorScheme, contentScheme)
                .environment(\.backdropScheme, nil)

        case .glass, .dualLayerGlass, .liquidGlass:
            // Only apply the overall glass tint when fully highlighted without a partial slider fill.
            // When fill < 1 (e.g. a light at 40% or fan at 25%), levelFill draws the colored portion,
            // leaving the remaining slider track untinted.
            let activeTint = (isHighlighted && fill >= 1) ? tint : nil
            inner.widgetGlass(in: shape, tint: activeTint, dimsWhenDark: !isHighlighted || fill < 1)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
    }
}

public extension View {
    /// The glass widgets are drawn on (`GlassTile`), in any shape, for
    /// something that sits among widgets without being a tile, such as a
    /// face's mini widget. Clear Liquid Glass, darkened over a dark backdrop,
    /// over a thin material unless the backdrop is already blurred, with its
    /// content in the backdrop's scheme (`glassBackdrop(_:)`): dark with light
    /// text over a dark face, light with dark text over a bright one.
    /// - Parameters:
    ///   - tint: Tints the whole glass, for a tile that is fully on.
    ///   - dimsWhenDark: False for a tile its tint or level fill already covers.
    func widgetGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, dimsWhenDark: Bool = true) -> some View {
        modifier(WidgetGlassModifier(shape: shape, tint: tint, dimsWhenDark: dimsWhenDark))
    }
}

private struct WidgetGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let dimsWhenDark: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.backdropScheme) private var backdropScheme
    @Environment(\.isBackdropBlurred) private var isBackdropBlurred

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark || backdropScheme == .dark
        let glass = (tint.map { Glass.clear.tint($0) } ?? Glass.clear).interactive()
        content
            .background {
                if isDark && dimsWhenDark {
                    shape.fill(Color.black.opacity(0.30))
                }
            }
            .tileGlassEffect(glass, in: shape)
            .background {
                if !isBackdropBlurred {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .nightModeAware()
            .environment(\.colorScheme, isDark ? .dark : (backdropScheme ?? colorScheme))
            .environment(\.backdropScheme, nil)
    }
}
