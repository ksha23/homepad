import HomePadUI
import SwiftUI

/// A Home Screen wallpaper: the current face behind frosted glass, one of a
/// few curated gradients, or one photo.
enum WallpaperChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The face that is showing, frosted, as on HomeView. The default.
    case face
    /// The member's own accent color fading to black.
    case accent
    case dusk, ocean, forest, ember, graphite
    /// A photo the member picked, stored by `WallpaperPhotoStore`.
    case photo

    static let standard = WallpaperChoice.face

    var id: String { rawValue }

    var title: String {
        switch self {
        case .face: "Face"
        case .accent: "My Color"
        case .dusk: "Dusk"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .ember: "Ember"
        case .graphite: "Graphite"
        case .photo: "Photo"
        }
    }

    /// The gradient's colors, top to bottom. `accent` mixes in the member's color.
    func colors(accent: Color) -> [Color] {
        switch self {
        case .accent: [accent.opacity(0.85), accent.opacity(0.35), .black]
        case .dusk: [Color(hex: "#3A1C71"), Color(hex: "#D76D77"), Color(hex: "#FFAF7B")]
        case .ocean: [Color(hex: "#0B3D91"), Color(hex: "#1CA7EC"), Color(hex: "#0A1F33")]
        case .forest: [Color(hex: "#134E5E"), Color(hex: "#3F7D58"), Color(hex: "#0B1F14")]
        case .ember: [Color(hex: "#7A1F1F"), Color(hex: "#E65C00"), Color(hex: "#1E0A05")]
        case .graphite, .photo, .face: [Color(hex: "#3A3A3C"), Color(hex: "#1C1C1E"), .black]
        }
    }

    /// How bright the gradient is, drawn on black as the wallpaper draws it,
    /// before the Home Screen's scrim.
    func tone(accent: Color) -> BackdropTone {
        .gradient(colors(accent: accent).map(BackdropTone.init))
    }

    /// Gradients offered in the picker (the face and photo options are separate).
    static var gradients: [WallpaperChoice] { allCases.filter { $0 != .photo && $0 != .face } }
}
