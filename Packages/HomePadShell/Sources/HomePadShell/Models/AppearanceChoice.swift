import SwiftUI

/// Light or dark for the whole app, in Kiosk & Display. `.automatic` follows
/// the iPad's own setting. The solid widget cards (Calendar, Reminders,
/// Timers) are white in light and black in dark, and black at night either way.
enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Match iPad"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The color scheme to ask for, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Cycles between dark mode, light mode, and matching the iPad system appearance.
    var next: AppearanceChoice {
        switch self {
        case .dark: .light
        case .light: .automatic
        case .automatic: .dark
        }
    }

    /// Short label for compact controls such as Control Center.
    var shortTitle: String {
        switch self {
        case .automatic: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// SF Symbol representing this appearance state.
    var systemImage: String {
        switch self {
        case .automatic: "arrow.triangle.2.circlepath"
        case .light: "sun.max.fill"
        case .dark: "circle.lefthalf.filled"
        }
    }
}
