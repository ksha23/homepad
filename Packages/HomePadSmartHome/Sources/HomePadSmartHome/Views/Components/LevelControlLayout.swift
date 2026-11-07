import CoreGraphics
import HomePadUI

/// Where `LevelControl` draws its fill, its symbol and its value for a level.
///
/// The symbol rides the fill line, with the line across its lower part, as
/// HomeView's bulb sits on it. The value sits just under the symbol, on the
/// color, while the fill is tall enough to hold it, and above the symbol on
/// the empty part once it is not. Both stay inside the control's padding.
struct LevelControlLayout: Equatable {
    /// The value's font size: about a fifth of the screen's height in digits.
    let valueSize: CGFloat
    /// The symbol's font size.
    let symbolSize: CGFloat
    /// How tall the color is, from the bottom.
    let fillHeight: CGFloat
    /// The symbol's center, from the top.
    let symbolCenterY: CGFloat
    /// The value's center, from the top.
    let valueCenterY: CGFloat
    /// True while the value sits on the color, under the symbol.
    let valueIsOnFill: Bool

    /// The room kept between the content and the control's edges.
    static let padding = Theme.Spacing.l

    init(size: CGSize, level: Double) {
        let height = max(size.height, 0)
        let padding = Self.padding
        valueSize = max(min(height * 0.33, size.width * 0.36), 0)
        symbolSize = valueSize * 0.3
        fillHeight = height * CGFloat(min(max(level, 0), 1))

        // The drawn heights, a little more than the glyphs, for the checks below.
        let symbolHeight = symbolSize * 1.2
        let valueHeight = valueSize * 0.85
        let gap = Theme.Spacing.m

        let line = height - fillHeight
        symbolCenterY = Self.clamp(line - symbolHeight * 0.2, half: symbolHeight / 2, padding: padding, height: height)
        let below = symbolCenterY + symbolHeight / 2 + gap + valueHeight / 2
        valueIsOnFill = below + valueHeight / 2 <= height - padding
        let above = symbolCenterY - symbolHeight / 2 - gap - valueHeight / 2
        valueCenterY = Self.clamp(valueIsOnFill ? below : above, half: valueHeight / 2, padding: padding, height: height)
    }

    private static func clamp(_ center: CGFloat, half: CGFloat, padding: CGFloat, height: CGFloat) -> CGFloat {
        let low = padding + half
        let high = height - padding - half
        guard low <= high else { return height / 2 }
        return min(max(center, low), high)
    }
}
