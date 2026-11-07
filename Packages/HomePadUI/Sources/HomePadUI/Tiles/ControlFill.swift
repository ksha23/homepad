import SwiftUI

/// What a glass tile's own surface looks like over its backdrop, worked out
/// from the backdrop's tone, so the controls in the tile can take a fill that
/// shows on it (`ControlFill`).
///
/// Glass pulls whatever is behind it toward a color of its own. Light glass
/// pulls it toward white and dark glass toward a dark gray. These numbers were
/// measured from `GlassTile` in the iPadOS 27 simulator over flat face
/// backgrounds and Home Screen wallpapers, and agree with a device screenshot
/// over a photo:
///
/// - Light glass covers its backdrop with white, about 65 percent of the way
///   with its frosted base (on a face) and 60 percent where the backdrop is
///   already blurred (the Home Screen's Face wallpaper).
/// - Dark glass, with the tile's black backing, covers it with a gray of sRGB
///   0.27, about 61 percent of the way with its frosted base and 35 percent on
///   a blurred backdrop. A near black face comes out a little lighter, and a
///   bright one in Dark comes out middle gray.
enum GlassSurface {
    /// The sRGB gray glass pulls its backdrop toward, and how far, from 0 to 1.
    struct Cover: Equatable {
        var gray: Double
        var amount: Double
    }

    static func cover(scheme: ColorScheme, isBackdropBlurred: Bool) -> Cover {
        switch (scheme, isBackdropBlurred) {
        case (.light, false): Cover(gray: 1, amount: 0.65)
        case (.light, true): Cover(gray: 1, amount: 0.6)
        case (_, false): Cover(gray: 0.27, amount: 0.61)
        case (_, true): Cover(gray: 0.27, amount: 0.35)
        }
    }

    /// The tone of glass in `scheme` laid over a backdrop of `backdrop`.
    static func tone(over backdrop: BackdropTone, scheme: ColorScheme, isBackdropBlurred: Bool = false) -> BackdropTone {
        let cover = cover(scheme: scheme, isBackdropBlurred: isBackdropBlurred)
        let gray = backdrop.gray * (1 - cover.amount) + cover.gray * cover.amount
        return BackdropTone(red: gray, green: gray, blue: gray)
    }
}

/// The fill behind a control in a tile that has nothing lit to show: a light
/// that is off, the empty part of a dimmed light's row, a scene, a chip
/// (`controlSurface(_:)`).
///
/// It is white or black at an opacity, like Apple's own fills (`systemFill`
/// and its siblings): a translucent gray that darkens a light surface and
/// lightens a dark one. That is how iOS draws a control on a white surface in
/// Light, such as a search field, and how Control Center draws its modules
/// lighter than its dark glass. Being translucent, the fill keeps the glass
/// and its blur showing through.
///
/// The rule works from the tile's surface (`GlassSurface`):
///
/// - A surface darker than `BackdropTone.midpoint` gets a lighter fill and a
///   brighter one a darker fill, toward whichever end has more contrast to give.
/// - The opacity is the faintest that reaches `minimumContrast` against the
///   surface, and never fainter than `faintest`, the white Dark has always drawn.
public struct ControlFill: Equatable, Sendable {
    /// True for a white fill, which lightens the surface, and false for a
    /// black one, which darkens it.
    public var isLighter: Bool
    /// From 0 to 1.
    public var opacity: Double

    /// The WCAG contrast a control's fill reaches against its tile. It is what
    /// the rows in Dark already had on dark glass (1.42 to 1.47 measured), so
    /// Light reads the same. Apple's `systemFill` on white is about 1.28, and a
    /// display read from a few steps away needs a little more.
    public static let minimumContrast = 1.4

    /// The faintest fill, white at 12 percent, as on dark glass before. It
    /// already reaches the contrast there.
    public static let faintest = 0.12

    public init(isLighter: Bool, opacity: Double) {
        self.isLighter = isLighter
        self.opacity = min(max(opacity, 0), 1)
    }

    /// The fill for a control on a surface of `surface`.
    public init(on surface: BackdropTone) {
        let gray = surface.gray
        let isLighter = surface.luminance < BackdropTone.midpoint
        let needed: Double
        if isLighter {
            // White at opacity a takes the gray to gray + (1 - gray) * a.
            let goal = BackdropTone(luminance: Self.minimumContrast * (surface.luminance + 0.05) - 0.05).gray
            needed = gray >= 1 ? 1 : (goal - gray) / (1 - gray)
        } else {
            // Black at opacity a takes the gray to gray * (1 - a).
            let goal = BackdropTone(luminance: (surface.luminance + 0.05) / Self.minimumContrast - 0.05).gray
            needed = gray <= 0 ? 0 : 1 - goal / gray
        }
        self.init(isLighter: isLighter, opacity: max(needed, Self.faintest))
    }

    /// The surface with this fill drawn over it. The screen blends in sRGB, so
    /// the fill mixes the gray values, not the luminance.
    public func tone(over surface: BackdropTone) -> BackdropTone {
        let gray = surface.gray
        let mixed = isLighter ? gray + (1 - gray) * opacity : gray * (1 - opacity)
        return BackdropTone(red: mixed, green: mixed, blue: mixed)
    }

    /// The WCAG contrast between the filled control and the surface around it.
    public func contrast(on surface: BackdropTone) -> Double {
        tone(over: surface).contrast(with: surface)
    }

    public var color: Color {
        (isLighter ? Color.white : Color.black).opacity(opacity)
    }
}

extension BackdropTone {
    /// The sRGB value, from 0 to 1, of the gray with this luminance.
    var gray: Double {
        luminance <= 0.003_130_8 ? luminance * 12.92 : 1.055 * pow(luminance, 1 / 2.4) - 0.055
    }

    /// The WCAG contrast between two tones, from 1 to 21.
    func contrast(with other: BackdropTone) -> Double {
        let (light, dark) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (light + 0.05) / (dark + 0.05)
    }
}

public extension EnvironmentValues {
    /// How bright the surface of the tile that holds this view is. `GlassTile`
    /// sets it for its content from its backdrop's tone, its look and the
    /// blur behind it. Nil outside a tile, where `controlSurface(_:)` takes
    /// glass over the page color.
    @Entry var tileSurfaceTone: BackdropTone? = nil
}
