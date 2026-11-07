import HomePadUI
import SwiftUI

/// The curated text colors a face's numerals and words can take instead of
/// the background's own. Light ones read on dark backgrounds and dark ones on
/// light backgrounds. The dark ones are the presets' own inks, so they are
/// known to sit well on the light backgrounds. Saved faces store the raw value
/// under `FaceColorChoice.textKey`.
enum FaceTextColor: String, CaseIterable, Identifiable, Sendable {
    case white, cream, blush, sky, mint, lilac
    case black, navy, indigo, forest, cocoa, berry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "White"
        case .cream: "Cream"
        case .blush: "Blush"
        case .sky: "Sky"
        case .mint: "Mint"
        case .lilac: "Lilac"
        case .black: "Black"
        case .navy: "Navy"
        case .indigo: "Indigo"
        case .forest: "Forest"
        case .cocoa: "Cocoa"
        case .berry: "Berry"
        }
    }

    var rgb: FaceRGB {
        switch self {
        case .white: FaceRGB(hex: "#FFFFFF")
        case .cream: FaceRGB(hex: "#FFF1D6")
        case .blush: FaceRGB(hex: "#FFD6DE")
        case .sky: FaceRGB(hex: "#D4E8FF")
        case .mint: FaceRGB(hex: "#D2F4E0")
        case .lilac: FaceRGB(hex: "#E4DCFF")
        case .black: FaceRGB(hex: "#1C1C1E")
        case .navy: FaceRGB(hex: "#0F2F52")
        case .indigo: FaceRGB(hex: "#4B4592")
        case .forest: FaceRGB(hex: "#24402A")
        case .cocoa: FaceRGB(hex: "#4A3B24")
        case .berry: FaceRGB(hex: "#5E2F36")
        }
    }

    /// The light text colors, the ones that read over a photo with a soft shadow.
    static let light: [FaceTextColor] = [.white, .cream, .blush, .sky, .mint, .lilac]
}

/// An accent color: one of the eight member colors in `Theme.Palette`, so
/// faces use the same accents as the rest of HomePad. Saved faces store the
/// swatch's ID under `FaceColorChoice.accentKey`.
struct FaceAccent: Hashable, Identifiable, Sendable {
    let swatch: Theme.Palette.Swatch

    var id: String { swatch.id }
    var title: String { swatch.name }
    var rgb: FaceRGB { FaceRGB(hex: swatch.hex) }

    /// The accent with an ID, or nil when it is not one of the member colors.
    init?(id: String) {
        guard let swatch = Theme.Palette.swatches.first(where: { $0.id == id }) else { return nil }
        self.swatch = swatch
    }

    private init(swatch: Theme.Palette.Swatch) {
        self.swatch = swatch
    }

    /// Every accent, in the member palette's order.
    static var all: [FaceAccent] { Theme.Palette.swatches.map(FaceAccent.init(swatch:)) }
}
