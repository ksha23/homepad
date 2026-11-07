import Foundation

/// The parts of a face its Color page can color besides the background.
struct FaceColorRoles: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// Numerals and words.
    static let text = FaceColorRoles(rawValue: 1 << 0)
    /// The highlighted parts, such as the weekday, event bars and second hand.
    static let accent = FaceColorRoles(rawValue: 1 << 1)
    /// With `accent`: the accent mostly fills tiles that are on (the Home
    /// face), where it is drawn as it is, so the editor's swatches show it so.
    static let accentFillsTiles = FaceColorRoles(rawValue: 1 << 2)
    static let all: FaceColorRoles = [.text, .accent]
}

/// What a person chose on a face's Color page: a background, and optionally
/// a text color and an accent of their own. Nil text or accent means
/// automatic: the colors designed with the background (`FacePreset`), which is
/// how every face looked before these choices existed.
///
/// The readability rule keeps every combination legible:
/// - A text color must reach `minimumContrast` against both ends of the
///   background's gradient. One that does not is unavailable on that
///   background: the editor dims it, and a face whose background changed under
///   it draws the background's own text until a background it reads on returns.
/// - An accent keeps its hue but is deepened on light backgrounds or lightened
///   on dark ones, just enough to reach the same contrast.
struct FaceColorChoice: Hashable, Sendable {
    /// Where a face configuration stores the text color. New in October 2026,
    /// so faces saved before have none and stay automatic.
    static let textKey = "textColor"
    /// Where a face configuration stores the accent.
    static let accentKey = "accentColor"
    /// WCAG's minimum contrast for large text. Face text is large display type.
    static let minimumContrast = 3.0

    var background: FaceColor
    var text: FaceTextColor?
    var accent: FaceAccent?

    init(background: FaceColor, text: FaceTextColor? = nil, accent: FaceAccent? = nil) {
        self.background = background
        self.text = text
        self.accent = accent
    }

    /// The text color the face draws: the chosen one when it reads on the
    /// background, otherwise nil for the background's own.
    var effectiveText: FaceTextColor? {
        guard let text, Self.isReadable(text, on: background) else { return nil }
        return text
    }

    /// Whether a text color reads on a background: at least `minimumContrast`
    /// against both ends of its gradient.
    static func isReadable(_ text: FaceTextColor, on background: FaceColor) -> Bool {
        worstContrast(of: text.rgb, on: background.preset) >= minimumContrast
    }

    /// The accent as a face draws it on a background (see `readableShade`).
    static func shade(of accent: FaceAccent, on background: FaceColor) -> FaceRGB {
        readableShade(of: accent.rgb, on: background.preset)
    }

    /// A color moved toward black or white, whichever needs the smaller step,
    /// just far enough to reach `minimumContrast` against both ends of the
    /// background. A color that already does is returned as it is. When
    /// neither direction gets there, the end with the better contrast wins.
    static func readableShade(of color: FaceRGB, on preset: FacePreset) -> FaceRGB {
        if worstContrast(of: color, on: preset) >= minimumContrast { return color }
        var best: (shade: FaceRGB, step: Double)?
        for end in [FaceRGB.black, .white] where worstContrast(of: end, on: preset) >= minimumContrast {
            // Contrast grows steadily on the way to the end, so halving finds
            // the smallest step that is enough.
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if worstContrast(of: color.mixed(with: end, by: middle), on: preset) >= minimumContrast {
                    high = middle
                } else {
                    low = middle
                }
            }
            if high < best?.step ?? .infinity { best = (color.mixed(with: end, by: high), high) }
        }
        if let best { return best.shade }
        return worstContrast(of: .black, on: preset) >= worstContrast(of: .white, on: preset) ? .black : .white
    }

    /// The lower of a color's contrasts with the top and the bottom of a background.
    static func worstContrast(of color: FaceRGB, on preset: FacePreset) -> Double {
        min(color.contrast(with: preset.top), color.contrast(with: preset.bottom))
    }

    /// "Ocean", or "Ocean, Navy Text, Pink Accent" when text or an accent is chosen.
    var caption: String {
        var parts = [background.title]
        if let effectiveText { parts.append("\(effectiveText.title) Text") }
        if let accent { parts.append("\(accent.title) Accent") }
        return parts.joined(separator: ", ")
    }
}

/// The colors a face draws with, as numbers: a background's preset with the
/// chosen text and accent applied. `FacePalette` turns it into SwiftUI colors.
struct FaceColorSet: Equatable, Sendable {
    var top: FaceRGB
    var bottom: FaceRGB
    var ink: FaceRGB
    var secondary: FaceRGB
    var accent: FaceRGB
    var tile: FaceRGB
    /// The fill of a Home face tile that is on: the preset's tile, or the chosen accent.
    var highlight: FaceRGB
    /// Text and symbols on `highlight`.
    var onHighlight: FaceRGB
    /// Text on a white bubble, such as Sprig's "Timer is done!".
    var inkOnWhite: FaceRGB
    var isLight: Bool
    var hasChosenText: Bool
    var hasChosenAccent: Bool

    /// How far secondary text sits from the text toward the background. The
    /// presets' own secondary colors sit about this far.
    static let secondaryMix = 0.4

    init(_ choice: FaceColorChoice) {
        let preset = choice.background.preset
        top = preset.top
        bottom = preset.bottom
        tile = preset.tile
        isLight = preset.isLight
        let presetOnHighlight = preset.isLight ? preset.ink : preset.bottom

        if let text = choice.effectiveText {
            ink = text.rgb
            secondary = text.rgb.mixed(with: preset.middle, by: Self.secondaryMix)
            hasChosenText = true
        } else {
            ink = preset.ink
            secondary = preset.secondary
            hasChosenText = false
        }

        if let chosen = choice.accent {
            accent = FaceColorChoice.readableShade(of: chosen.rgb, on: preset)
            highlight = chosen.rgb
            hasChosenAccent = true
        } else {
            accent = preset.accent
            highlight = preset.tile
            hasChosenAccent = false
        }

        // Untouched faces keep their tiles exactly. Otherwise the text color
        // when it reads on the tile, then the preset's, then black or white.
        if hasChosenText || hasChosenAccent {
            onHighlight = Self.firstReadable([ink, presetOnHighlight, FaceTextColor.black.rgb, .white], on: highlight)
        } else {
            onHighlight = presetOnHighlight
        }
        inkOnWhite = Self.firstReadable([ink, FaceTextColor.black.rgb], on: .white)
    }

    /// The first color that reaches the minimum contrast on a fill, or the one
    /// with the most contrast when none does.
    static func firstReadable(_ candidates: [FaceRGB], on fill: FaceRGB) -> FaceRGB {
        if let readable = candidates.first(where: { $0.contrast(with: fill) >= FaceColorChoice.minimumContrast }) {
            return readable
        }
        return candidates.max { $0.contrast(with: fill) < $1.contrast(with: fill) } ?? .black
    }
}
