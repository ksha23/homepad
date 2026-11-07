import HomePadCore
import SwiftUI

/// The assistant's signature glow colors, in one place so the orb, the edge
/// glow and the app icon tint stay identical. Only the assistant uses
/// these colors, so they stay in this module.
enum AssistantPalette {
    static let glow: [Color] = [
        Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 1.0, green: 0.30, blue: 0.55),
        Color(red: 0.62, green: 0.35, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 1.0),
        Color(red: 0.30, green: 0.85, blue: 0.95), Color(red: 1.0, green: 0.55, blue: 0.25),
    ]

    /// Accent for assistant chrome such as the app icon tile.
    static let accent = Color.indigo

    /// How lively the glow is in each phase: rotation speed in degrees per second and strength 0 to 1.
    static func motion(for phase: AssistantPhase) -> (speed: Double, strength: Double) {
        switch phase {
        case .idle: (18, 0.35)
        case .listening: (40, 0.85)
        case .thinking: (140, 1.0)
        case .speaking: (60, 0.75)
        case .error: (10, 0.25)
        }
    }
}
