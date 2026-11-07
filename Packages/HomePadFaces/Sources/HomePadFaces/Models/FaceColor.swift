import SwiftUI

/// The fixed list of face backgrounds. Curated like the watchOS face editor:
/// a short list of named colors, never free-form hex. Each one is a preset
/// (`FacePreset`): a background with the text and accent colors designed
/// with it, which a face draws until the person picks its own text or accent
/// (`FaceColorChoice`). Saved faces store the raw value under the "color" key.
enum FaceColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case porcelain, graphite, lavender, midnight, ocean, sage, green, coral, sand, rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .porcelain: "Porcelain"
        case .graphite: "Graphite"
        case .lavender: "Lavender"
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .sage: "Sage"
        case .green: "Clover"
        case .coral: "Coral"
        case .sand: "Sand"
        case .rose: "Rose"
        }
    }

    /// The background and the colors designed with it.
    var preset: FacePreset {
        switch self {
        case .porcelain:
            FacePreset(top: "#F4F4F6", bottom: "#E1E1E6", ink: "#1C1C1E", secondary: "#6E6E73", accent: "#E0338B", tile: "#FFFFFF", isLight: true)
        case .graphite:
            FacePreset(top: "#2E2E33", bottom: "#111113", ink: "#FFFFFF", secondary: "#A1A1A6", accent: "#FF9F0A", tile: "#4A4A50", isLight: false)
        case .lavender:
            FacePreset(top: "#EEECFA", bottom: "#D6D0F2", ink: "#4B4592", secondary: "#8C86C6", accent: "#6E62D9", tile: "#C6BFEE", isLight: true)
        case .midnight:
            FacePreset(top: "#5357E6", bottom: "#202088", ink: "#FFFFFF", secondary: "#C9CBFF", accent: "#9EA3FF", tile: "#E9E9FF", isLight: false)
        case .ocean:
            FacePreset(top: "#D3E5F5", bottom: "#86B2DC", ink: "#0F2F52", secondary: "#3E6A94", accent: "#0A6FD8", tile: "#EAF3FB", isLight: true)
        case .sage:
            FacePreset(top: "#E6EEE2", bottom: "#BCD1B5", ink: "#24402A", secondary: "#5B7A5F", accent: "#2F8F4E", tile: "#F3F7F0", isLight: true)
        case .green:
            FacePreset(top: "#4CA56A", bottom: "#2E7D49", ink: "#0B1A10", secondary: "#173D24", accent: "#FFFFFF", tile: "#79C792", isLight: true)
        case .coral:
            FacePreset(top: "#F9D3C7", bottom: "#EA8C79", ink: "#5A1E14", secondary: "#8F3B2C", accent: "#D93B2B", tile: "#FCE5DD", isLight: true)
        case .sand:
            FacePreset(top: "#F1E9DA", bottom: "#D7C4A3", ink: "#4A3B24", secondary: "#85704E", accent: "#B5651D", tile: "#F8F2E7", isLight: true)
        case .rose:
            FacePreset(top: "#EEDADA", bottom: "#D3B0B4", ink: "#5E2F36", secondary: "#9A6A70", accent: "#E0338B", tile: "#F6E9E9", isLight: true)
        }
    }

    /// Colors for this background in daylight, with its own text and accent.
    var palette: FacePalette { FacePalette(FaceColorChoice(background: self)) }

    /// The swatch shown in the editor: the background gradient.
    var swatch: LinearGradient { palette.background }
}

/// A background and the text and accent colors designed with it, as numbers.
struct FacePreset: Sendable {
    /// The background runs from `top` to `bottom`.
    let top: FaceRGB
    let bottom: FaceRGB
    /// Numerals and words.
    let ink: FaceRGB
    /// Quieter words: captions, ticks, the high and low.
    let secondary: FaceRGB
    /// The highlighted parts: weekday, event bars, location arrow, second hand.
    let accent: FaceRGB
    /// The Home face's tiles that are on, and its backdrop shapes.
    let tile: FaceRGB
    /// True when the background is light and the text dark.
    let isLight: Bool

    init(top: String, bottom: String, ink: String, secondary: String, accent: String, tile: String, isLight: Bool) {
        self.top = FaceRGB(hex: top)
        self.bottom = FaceRGB(hex: bottom)
        self.ink = FaceRGB(hex: ink)
        self.secondary = FaceRGB(hex: secondary)
        self.accent = FaceRGB(hex: accent)
        self.tile = FaceRGB(hex: tile)
        self.isLight = isLight
    }

    /// The color halfway down the background.
    var middle: FaceRGB { top.mixed(with: bottom, by: 0.5) }
}
