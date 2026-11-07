import CoreText
import UIKit

/// A clock font's shape at a size of 1, so a big time can be placed by where
/// its digits are drawn. `Text` lays a time out in a whole line of type, with
/// room above the digits for accents and below for descenders.
struct ClockFontMetrics: Equatable, Sendable {
    /// The widest time the clock shows: two hour digits and two minute digits.
    var width: CGFloat
    /// The height of the line `Text` lays the time out in.
    var lineHeight: CGFloat
    /// From the top of that line down to the top of the digits.
    var digitTop: CGFloat
    /// From the top of the digits to their bottom.
    var digitHeight: CGFloat

    /// Measures `font` with the widest time of the hour cycle in use.
    static func measure(_ font: UIFont, uses24Hour: Bool) -> ClockFontMetrics {
        let sample = uses24Hour ? "00:00" : "10:00"
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: font]))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let size = max(font.pointSize, 1)
        return ClockFontMetrics(width: advance / size, lineHeight: font.lineHeight / size,
                                digitTop: (font.ascender - glyphs.maxY) / size, digitHeight: glyphs.height / size)
    }

    /// The Photos face's depth numerals: SF Pro Compressed Semibold (`PhotoClock.depthFont`).
    static func depth(uses24Hour: Bool) -> ClockFontMetrics {
        uses24Hour ? depth24 : depth12
    }

    /// The Photos face's classic time: SF Pro Rounded Semibold (`Font.display`).
    static func rounded(uses24Hour: Bool) -> ClockFontMetrics {
        uses24Hour ? rounded24 : rounded12
    }

    private static let depth12 = measure(compressedFont, uses24Hour: false)
    private static let depth24 = measure(compressedFont, uses24Hour: true)
    private static let rounded12 = measure(roundedFont, uses24Hour: false)
    private static let rounded24 = measure(roundedFont, uses24Hour: true)

    private static var compressedFont: UIFont {
        UIFont.systemFont(ofSize: 100, weight: .semibold, width: .compressed)
    }

    private static var roundedFont: UIFont {
        let font = UIFont.systemFont(ofSize: 100, weight: .semibold)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 100) } ?? font
    }
}
