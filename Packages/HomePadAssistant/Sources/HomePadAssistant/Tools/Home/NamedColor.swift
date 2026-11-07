import Foundation

/// Spoken color names mapped to hue and saturation, or to a white temperature.
enum NamedColor: Equatable {
    case hue(Double, saturation: Double)
    case white(kelvin: Int)

    private static let hues: [String: (Double, Double)] = [
        "red": (0, 1), "orange": (30, 1), "amber": (40, 1), "yellow": (55, 1), "lime": (90, 1),
        "green": (120, 1), "mint": (150, 0.5), "teal": (175, 1), "cyan": (185, 1), "turquoise": (175, 0.8),
        "blue": (230, 1), "sky blue": (200, 0.6), "indigo": (255, 1), "purple": (275, 1), "violet": (270, 0.8),
        "lavender": (270, 0.4), "magenta": (300, 1), "pink": (330, 0.6), "hot pink": (330, 1), "rose": (345, 0.7),
    ]
    private static let whites: [String: Int] = [
        "white": 4000, "warm white": 2700, "warm": 2700, "soft white": 2700, "candlelight": 2200,
        "neutral": 4000, "cool white": 5500, "cool": 5500, "daylight": 6500,
    ]

    init?(_ name: String) {
        let key = DeviceTargetResolver.normalize(name)
        if let (hue, saturation) = Self.hues[key] {
            self = .hue(hue, saturation: saturation)
        } else if let kelvin = Self.whites[key] {
            self = .white(kelvin: kelvin)
        } else {
            return nil
        }
    }
}
