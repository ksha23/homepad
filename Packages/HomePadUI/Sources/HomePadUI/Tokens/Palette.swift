import HomePadCore
import SwiftUI

public extension Theme {
    /// The curated accent colors people can pick for themselves (avatar ring,
    /// Home Screen accent). A short fixed list, the way Apple offers choices,
    /// instead of free-form color entry.
    enum Palette {
        /// One curated color.
        public struct Swatch: Identifiable, Hashable, Sendable {
            public let id: String
            public let name: String
            /// "#RRGGBB", the format `HouseholdMember.colorHex` stores.
            public let hex: String

            public var color: Color { Color(hex: hex) }
        }

        /// The eight member colors, in display order. The first is the default.
        public static let swatches: [Swatch] = [
            Swatch(id: "blue", name: "Blue", hex: "#0A84FF"),
            Swatch(id: "purple", name: "Purple", hex: "#BF5AF2"),
            Swatch(id: "pink", name: "Pink", hex: "#FF375F"),
            Swatch(id: "red", name: "Red", hex: "#FF453A"),
            Swatch(id: "orange", name: "Orange", hex: "#FF9F0A"),
            Swatch(id: "yellow", name: "Yellow", hex: "#FFD60A"),
            Swatch(id: "green", name: "Green", hex: "#30D158"),
            Swatch(id: "teal", name: "Teal", hex: "#40C8E0"),
        ]

        /// The swatch for a stored hex value, or nil when it is not one of the curated colors.
        public static func swatch(forHex hex: String) -> Swatch? {
            swatches.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
        }
    }
}

/// A row of round color swatches for picking from `Theme.Palette`.
///
///     PaletteSwatchPicker(selection: $member.colorHex)
public struct PaletteSwatchPicker: View {
    @Binding private var selection: String

    /// - Parameter selection: The chosen color as "#RRGGBB".
    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(Theme.Palette.swatches) { swatch in
                let isSelected = swatch.hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    selection = swatch.hex
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Circle().strokeBorder(.primary, lineWidth: isSelected ? 3 : 0).padding(-5)
                        }
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
