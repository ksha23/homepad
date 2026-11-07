import SwiftUI

/// The curated text sizes offered in Kiosk & Display. `.system` follows the
/// iPad's own Dynamic Type setting; the others pin a larger size for reading
/// from across the room.
enum TextSizeChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, large, extraLarge, huge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match iPad"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .huge: "Huge"
        }
    }

    /// The Dynamic Type size to pin, or nil to follow the system.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .large: .xLarge
        case .extraLarge: .xxLarge
        case .huge: .xxxLarge
        }
    }
}

extension View {
    /// Applies the chosen text size, or leaves the system size alone.
    @ViewBuilder
    func textSize(_ choice: TextSizeChoice) -> some View {
        if let size = choice.dynamicTypeSize {
            dynamicTypeSize(size)
        } else {
            self
        }
    }
}
