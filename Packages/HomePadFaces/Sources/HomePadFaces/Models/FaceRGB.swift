import HomePadUI
import SwiftUI

/// An sRGB color as numbers, so face colors can be compared and mixed in
/// plain code and tests. `color` turns it into the SwiftUI color a face draws,
/// the same one `Color(hex:)` makes from the same hex.
struct FaceRGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = FaceRGB(red: 1, green: 1, blue: 1)
    static let black = FaceRGB(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses "#RRGGBB" or "RRGGBB". Falls back to gray, as `Color(hex:)` does.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Relative luminance, as WCAG defines it: 0 for black, 1 for white.
    var luminance: Double {
        BackdropTone.luminance(red: red, green: green, blue: blue)
    }

    /// How bright this color is as a backdrop, for glass laid over it.
    var tone: BackdropTone { BackdropTone(luminance: luminance) }

    /// The WCAG contrast ratio between two colors, from 1 (the same) to 21
    /// (black on white).
    func contrast(with other: FaceRGB) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This color moved `fraction` of the way to `other`, channel by channel.
    func mixed(with other: FaceRGB, by fraction: Double) -> FaceRGB {
        let t = min(max(fraction, 0), 1)
        return FaceRGB(red: red + (other.red - red) * t,
                       green: green + (other.green - green) * t,
                       blue: blue + (other.blue - blue) * t)
    }
}
