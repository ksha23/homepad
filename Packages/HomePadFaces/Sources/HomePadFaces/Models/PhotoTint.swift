import Foundation
import HomePadUI

/// A plain RGB color that can cross actors, used for tints derived from photos.
struct PhotoTint: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = PhotoTint(red: 1, green: 1, blue: 1)

    /// How bright the photo is as a backdrop, from its average color, for
    /// glass laid over it.
    var tone: BackdropTone { BackdropTone(red: red, green: green, blue: blue) }

    /// A light, softly saturated version of a photo's average color, for
    /// numerals that feel part of the picture (HomeView's tinted time).
    func numeralTint() -> PhotoTint {
        let (hue, saturation, _) = hsv
        return PhotoTint(hue: hue, saturation: min(saturation, 0.6) * 0.6, value: 0.97)
    }

    /// Hue (0..<1), saturation and value (0...1).
    var hsv: (Double, Double, Double) {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let delta = maxValue - minValue
        guard maxValue > 0, delta > 0 else { return (0, 0, maxValue) }
        var hue: Double
        if maxValue == red {
            hue = (green - blue) / delta
        } else if maxValue == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue = (hue / 6).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return (hue, delta / maxValue, maxValue)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hue: Double, saturation: Double, value: Double) {
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let chroma = value * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - chroma
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}
