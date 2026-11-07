import CoreGraphics
import Foundation

/// Converts system colors (EventKit calendar colors) to the "#RRGGBB" strings
/// Core models carry. `Color(hex:)` in Core reads them back.
enum ColorHex {
    static let fallback = "#8E8E93"

    static func string(from color: CGColor?) -> String {
        guard let color,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else {
            return fallback
        }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(components[0]), channel(components[1]), channel(components[2]))
    }
}
