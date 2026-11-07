import HomePadCore
import SwiftUI

public extension View {
    /// Tints content red and dark when the display is in night mode.
    func nightModeAware() -> some View {
        modifier(NightModeModifier())
    }

    /// The surface of a control inside a tile (a light that is off, an accessory row,
    /// a scene). A translucent fill with no border, lighter than a dark tile and
    /// darker than a light one, just strong enough to stand out from the tile
    /// (`ControlFill`). Inside a `GlassTile` it follows the tile's own surface over
    /// its backdrop (`tileSurfaceTone`). Elsewhere it takes glass over the page.
    func controlSurface<S: InsettableShape>(_ shape: S) -> some View {
        modifier(ControlSurfaceModifier(shape: shape))
    }

    /// Fills the view with `tint` from the leading edge to `fraction` of its
    /// width, the way Control Center shows a light's brightness: 1 fills it, 0
    /// leaves it empty. Put the surface for the empty part behind this. Content
    /// is drawn twice, so `fillAwareForeground` text is black over the fill and
    /// the primary text color past it.
    func levelFill<S: Shape>(_ fraction: Double, tint: Color, in shape: S) -> some View {
        modifier(LevelFillModifier(fraction: min(max(fraction, 0), 1), tint: tint, shape: shape))
    }

    /// Black over a `levelFill`'s color, and the primary text color past it.
    func fillAwareForeground() -> some View {
        modifier(FillAwareForeground())
    }
}

struct LevelFillModifier<S: Shape>: ViewModifier {
    let fraction: Double
    let tint: Color
    let shape: S

    func body(content: Content) -> some View {
        let isPartial = fraction > 0 && fraction < 1
        content
            .environment(\.isOverFill, fraction >= 1)
            .overlay {
                if isPartial {
                    content
                        .environment(\.isOverFill, true)
                        .mask(alignment: .leading) { filledPart }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background { filledPart.foregroundStyle(tint.opacity(0.9)).clipShape(shape) }
            .animation(.smooth, value: fraction)
    }

    private var filledPart: some View {
        GeometryReader { proxy in
            Rectangle().frame(width: proxy.size.width * fraction)
        }
    }
}

struct FillAwareForeground: ViewModifier {
    @Environment(\.isOverFill) private var isOverFill

    func body(content: Content) -> some View {
        // Past the fill, the text color of the appearance: white in Dark, black
        // in Light. A fixed white vanished on white tiles in Light.
        content.foregroundStyle(isOverFill ? Color.black : Color.primary)
    }
}

struct ControlSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tileSurfaceTone) private var tileSurface

    func body(content: Content) -> some View {
        // Outside a tile (Control Center, a popover, a detail page) the control
        // sits on glass over the page color.
        let page: BackdropTone = colorScheme == .light ? .white : .black
        let surface = tileSurface ?? GlassSurface.tone(over: page, scheme: colorScheme)
        content
            .background(shape.fill(ControlFill(on: surface).color))
    }
}

struct NightModeModifier: ViewModifier {
    @Environment(\.displayCondition) private var condition

    func body(content: Content) -> some View {
        if condition == .night {
            content
                .colorMultiply(Theme.nightRed)
                .saturation(1.2)
                .brightness(-0.1)
        } else {
            content
        }
    }
}

/// Shows `far` content from across the room and `near` content up close,
/// with a smooth transition as the person approaches (HomeView's distance-aware UI).
///
/// It crossfades two separate views. When both show the same text (a time, a
/// temperature) at different sizes or places, the two copies blur through each
/// other. Keep one view then and change its size and place (`scaleEffect`,
/// `position`, an animatable font size) with `Theme.Motion.proximity`.
public struct ProximityAdaptive<Far: View, Near: View>: View {
    @Environment(\.proximity) private var proximity
    private let far: Far
    private let near: Near

    public init(@ViewBuilder far: () -> Far, @ViewBuilder near: () -> Near) {
        self.far = far()
        self.near = near()
    }

    public var body: some View {
        ZStack {
            if proximity >= .mid {
                near.transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                far.transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(Theme.Motion.proximity, value: proximity >= .mid)
    }
}

public extension View {
    /// The soft shadow that keeps a white label readable on any wallpaper, for
    /// text on a scrolling page (Home Screen icon and widget names). The shadow
    /// is drawn once into the label's own layer. A live shadow is drawn again on
    /// every frame the page moves, and with a page of labels and icon shadows
    /// the Home Screen paged at 49 fps on an M4 iPad instead of 117.
    func wallpaperLabelShadow() -> some View {
        flattenedShadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    /// A shadow drawn once into the view's own layer. Use it instead of
    /// `.shadow` on anything near motion: a live shadow is drawn again on every
    /// frame that anything around it moves (a scrolling page, a Ken Burns photo,
    /// drifting clouds), and a flattened one redraws only when the view itself
    /// changes, such as a clock's minute.
    func flattenedShadow(color: Color, radius: CGFloat, y: CGFloat = 0) -> some View {
        // Room around the view so the shadow is not cut off at its layer's edge.
        let room = radius * 2 + abs(y)
        return shadow(color: color, radius: radius, y: y)
            .padding(room)
            .drawingGroup()
            .padding(-room)
    }
}
