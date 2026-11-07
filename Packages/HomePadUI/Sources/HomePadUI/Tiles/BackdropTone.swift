import HomePadCore
import SwiftUI

/// How bright a backdrop is: a face, a wallpaper or a photo that glass sits
/// on. Glass laid straight on a backdrop takes its light or dark look from
/// it, as iPadOS widgets do on a wallpaper: dark glass with light text over a
/// dark backdrop, light glass with dark text over a bright one, whatever the
/// Appearance setting.
///
/// Whatever draws a backdrop reports its tone with `backdropTone(_:)`. The
/// view that lays glass over it reads the report (`BackdropToneKey`) and hands
/// it to the glass with `glassBackdrop(_:)`, which sets `\.backdropScheme`.
/// Tones come from colors the backdrop already has, never from a list of
/// light and dark faces.
public struct BackdropTone: Equatable, Sendable {
    /// Relative luminance, as WCAG defines it: 0 for black, 1 for white.
    public var luminance: Double

    public init(luminance: Double) {
        self.luminance = min(max(luminance, 0), 1)
    }

    /// The tone of an sRGB color, channels from 0 to 1, drawn at `opacity`
    /// over black.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let alpha = min(max(opacity, 0), 1)
        self.init(luminance: Self.luminance(red: red * alpha, green: green * alpha, blue: blue * alpha))
    }

    /// The tone of a color, drawn over black when it is see-through.
    public init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue),
                  opacity: Double(resolved.opacity))
    }

    public static let black = BackdropTone(luminance: 0)
    public static let white = BackdropTone(luminance: 1)

    /// The tone of a gradient through evenly spaced stops, as a blur sees it:
    /// each stop counts for the band around it, so the two ends count half.
    public static func gradient(_ stops: [BackdropTone]) -> BackdropTone {
        guard stops.count > 1 else { return stops.first ?? .black }
        var total = 0.0
        var weights = 0.0
        for (index, stop) in stops.enumerated() {
            let weight = index == 0 || index == stops.count - 1 ? 0.5 : 1
            total += stop.luminance * weight
            weights += weight
        }
        return BackdropTone(luminance: total / weights)
    }

    /// The plain average of several tones, such as the colors of a mesh.
    public static func average(_ tones: [BackdropTone]) -> BackdropTone {
        guard !tones.isEmpty else { return .black }
        return BackdropTone(luminance: tones.map(\.luminance).reduce(0, +) / Double(tones.count))
    }

    /// The tone under a black scrim of `opacity`, such as the dimming the
    /// Home Screen lays over its wallpaper. The scrim scales each sRGB channel
    /// by one minus the opacity, which takes luminance down by about that to
    /// the power 2.2.
    public func dimmed(by opacity: Double) -> BackdropTone {
        BackdropTone(luminance: luminance * pow(1 - min(max(opacity, 0), 1), 2.2))
    }

    /// Where white text and black text read equally well on a backdrop, with
    /// a contrast of about 4.6 to 1 each. Luminance is about 0.18 there, a
    /// middle gray.
    public static let midpoint = (1.05 * 0.05).squareRoot() - 0.05

    /// How far past the midpoint a backdrop has to go to turn glass that is
    /// already light or dark the other way.
    public static let hysteresis = 0.04

    /// The color scheme glass takes on this backdrop. Pass the one it has
    /// now: a tone within `hysteresis` of the midpoint keeps it, so a
    /// backdrop near middle gray does not flip glass back and forth as its
    /// photo or sky changes a little.
    public func scheme(keeping current: ColorScheme? = nil) -> ColorScheme {
        switch current {
        case .light?: luminance < Self.midpoint - Self.hysteresis ? .dark : .light
        case .dark?: luminance > Self.midpoint + Self.hysteresis ? .light : .dark
        default: luminance >= Self.midpoint ? .light : .dark
        }
    }

    /// The WCAG contrast of white text on this backdrop, from 1 (on white)
    /// to 21 (on black).
    public var whiteTextContrast: Double { 1.05 / (luminance + 0.05) }

    /// How strong a black shade over an sRGB color (channels from 0 to 1)
    /// has to be for white text on it to reach `contrast`. It is the opacity
    /// of the lightest shade that is enough, and 0 where white already reads.
    ///
    /// A picture that keeps white text, such as a weather sky, lays this shade
    /// between itself and the text. It grows with the picture's brightness and
    /// is not there at all on a dark picture.
    public static func whiteTextShade(red: Double, green: Double, blue: Double, contrast: Double) -> Double {
        // A black shade of opacity s scales each channel by 1 - s, which is
        // the color drawn at opacity 1 - s over black.
        func reaches(_ shade: Double) -> Bool {
            BackdropTone(red: red, green: green, blue: blue, opacity: 1 - shade).whiteTextContrast >= contrast
        }
        if reaches(0) { return 0 }
        // Contrast grows steadily as the shade deepens, so halving finds the
        // lightest shade that is enough.
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if reaches(middle) {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    /// WCAG relative luminance of an sRGB color, channels from 0 to 1.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// Carries a backdrop's tone up to the view that lays glass over it. The
/// first report wins, so the backdrop at the bottom of a stack is the one
/// that counts.
public struct BackdropToneKey: PreferenceKey {
    public static let defaultValue: BackdropTone? = nil

    public static func reduce(value: inout BackdropTone?, nextValue: () -> BackdropTone?) {
        if value == nil { value = nextValue() }
    }
}

public extension EnvironmentValues {
    /// The color scheme of the backdrop that glass sits on (a face, the Home
    /// Screen's wallpaper), set by `glassBackdrop(_:)`. Nil on a page, where
    /// glass follows the appearance. `GlassTile` clears it for its content,
    /// which sits on the tile rather than on the backdrop.
    @Entry var backdropScheme: ColorScheme? = nil

    /// The tone of the backdrop that glass sits on, set by `glassBackdrop(_:)`
    /// with `backdropScheme`. `GlassTile` works out its own surface from it,
    /// for the controls inside (`tileSurfaceTone`), and clears it for its content.
    @Entry var glassBackdropTone: BackdropTone? = nil

    /// True when the backdrop behind glass is already blurred (such as the Home Screen's
    /// Face wallpaper), so glass tiles do not double up on blur and can use clear Liquid Glass directly.
    @Entry var isBackdropBlurred: Bool = false
}

public extension View {
    /// Reports the tone of the backdrop this view draws, for the glass that
    /// is laid over it. Nil reports nothing.
    func backdropTone(_ tone: BackdropTone?) -> some View {
        preference(key: BackdropToneKey.self, value: tone)
    }

    /// Glass in this view sits on a backdrop of `tone`, so `GlassTile` takes
    /// its light or dark look from the backdrop instead of the appearance.
    /// Nil leaves glass to the appearance, and at night glass stays dark.
    ///
    /// Put it on the views that hold the glass, not on one that presents a
    /// sheet, or the sheet takes it too.
    func glassBackdrop(_ tone: BackdropTone?) -> some View {
        modifier(GlassBackdropModifier(tone: tone))
    }

    /// Tells nested glass tiles whether the backdrop behind them is already blurred
    /// (e.g. the Home Screen's blurred wallpaper), so tiles avoid doubling up on blur.
    func backdropBlurred(_ isBlurred: Bool = true) -> some View {
        environment(\.isBackdropBlurred, isBlurred)
    }
}

private struct GlassBackdropModifier: ViewModifier {
    let tone: BackdropTone?
    @Environment(\.displayCondition) private var condition
    /// The scheme the glass has now, so a tone near the midpoint keeps it.
    @State private var current: ColorScheme?

    func body(content: Content) -> some View {
        // Night tints the screen red, which would turn light glass into a bright red block.
        let scheme: ColorScheme? = condition == .night ? .dark : tone?.scheme(keeping: current)
        content
            .environment(\.backdropScheme, scheme)
            .environment(\.glassBackdropTone, tone)
            .onChange(of: scheme, initial: true) { _, scheme in current = scheme }
    }
}
