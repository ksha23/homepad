import SwiftUI

/// Ring light strength in the Mirror app. A few curated steps, not a slider.
public enum RingLightLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, low, medium, high

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Width of the glowing edge as a fraction of the shorter screen side.
    var bandFraction: CGFloat {
        switch self {
        case .off: 0
        case .low: 0.035
        case .medium: 0.06
        case .high: 0.09
        }
    }

    /// Whether the screen brightness is raised to full while the light is on.
    var boostsScreen: Bool { self != .off }
}

/// Ring light color temperature. Three presets, like a real ring light.
public enum RingLightTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case warm, neutral, cool

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "Warm"
        case .neutral: "Neutral"
        case .cool: "Cool"
        }
    }

    /// The light's color, approximating 3200 K, 5000 K and 6500 K.
    var color: Color {
        switch self {
        case .warm: Color(red: 1.0, green: 0.84, blue: 0.66)
        case .neutral: Color(red: 1.0, green: 0.96, blue: 0.92)
        case .cool: Color(red: 0.92, green: 0.95, blue: 1.0)
        }
    }
}

/// Close-up face view or wide full-body view, like HomeView's Mirror.
///
/// With Center Stage, Close-Up lets it keep the person framed as they move,
/// and Full Body turns it off for the camera's whole view. Without Center
/// Stage the two are a fixed 2× and 1× zoom.
public enum MirrorFraming: String, Codable, CaseIterable, Identifiable, Sendable {
    // Stored values. `wide` is Full Body.
    case closeUp, wide

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .closeUp: "Close-Up"
        case .wide: "Full Body"
        }
    }

    var systemImage: String {
        switch self {
        case .closeUp: "person.crop.square"
        case .wide: "figure.stand"
        }
    }

    /// Zoom relative to the widest view, where Center Stage is not available.
    var zoom: CGFloat {
        switch self {
        case .closeUp: 2
        case .wide: 1
        }
    }

    /// Whether Center Stage frames the person, where it is available.
    var usesCenterStage: Bool { self == .closeUp }
}
