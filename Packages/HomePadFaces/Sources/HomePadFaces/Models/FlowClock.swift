import CoreGraphics
import SwiftUI

/// One character of the Flow face's time, built from rounded rectangles and
/// circles like HomeView's Flow face: a 1 is a tall slab with a dot, a 0 a
/// rounded block, a 6 and a 9 a rounded bowl with a slab and a dot, an 8 two
/// stacked drops, the other digits rounded bars, and the colon two small
/// spheres. Each is drawn as one drop (`FlowGlyphShape`).
///
/// Pieces are in a cell `width` wide and `FlowGlyph.height` tall.
enum FlowGlyph: Hashable, Sendable {
    case digit(Int)
    case colon

    /// A piece of a glyph.
    enum Piece: Equatable, Sendable {
        case rounded(CGRect, radius: CGFloat)
        case circle(center: CGPoint, radius: CGFloat)
        /// A rounded rectangle with a rounded hole, `thickness` from its edge.
        case bowl(CGRect, radius: CGFloat, thickness: CGFloat)
    }

    /// A digit cell's height, for a width of 1.
    static let height: CGFloat = 1.7
    /// The thickness of a digit's bars.
    static let stroke: CGFloat = 0.32
    /// The space between two glyphs.
    static let gap: CGFloat = 0.2

    var width: CGFloat {
        switch self {
        case .digit: 1
        case .colon: 0.3
        }
    }

    /// The glyphs for a time such as "10:09".
    static func glyphs(_ time: String) -> [FlowGlyph] {
        time.compactMap { character in
            if character == ":" { return .colon }
            return character.wholeNumberValue.map(FlowGlyph.digit)
        }
    }

    var pieces: [Piece] {
        switch self {
        case .colon:
            [.circle(center: CGPoint(x: 0.15, y: 0.58), radius: 0.15),
             .circle(center: CGPoint(x: 0.15, y: 1.12), radius: 0.15)]
        case .digit(0):
            [.rounded(CGRect(x: 0, y: 0, width: 1, height: Self.height), radius: 0.46)]
        case .digit(1):
            [.rounded(CGRect(x: 0.5, y: 0, width: 0.42, height: Self.height), radius: 0.21),
             .circle(center: CGPoint(x: 0.2, y: 0.25), radius: 0.17)]
        case .digit(8):
            [.circle(center: CGPoint(x: 0.5, y: 0.42), radius: 0.42),
             .circle(center: CGPoint(x: 0.5, y: 1.2), radius: 0.5)]
        case .digit(9):
            // The slab starts high on the bowl's side, so the two meet without a notch.
            [.bowl(CGRect(x: 0, y: 0, width: 1, height: 0.98), radius: 0.46, thickness: Self.stroke),
             .rounded(CGRect(x: 1 - Self.stroke, y: 0.3, width: Self.stroke, height: Self.height - 0.3),
                      radius: Self.stroke / 2),
             .circle(center: CGPoint(x: 0.24, y: Self.height - 0.2), radius: 0.17)]
        case .digit(6):
            [.bowl(CGRect(x: 0, y: Self.height - 0.98, width: 1, height: 0.98), radius: 0.46, thickness: Self.stroke),
             .rounded(CGRect(x: 0, y: 0, width: Self.stroke, height: Self.height - 0.3), radius: Self.stroke / 2),
             .circle(center: CGPoint(x: 0.76, y: 0.2), radius: 0.17)]
        case .digit(let value):
            Self.segments(for: value).map { Self.bar($0) }
        }
    }

    /// The seven bars of a segment display, a at the top round to g in the middle.
    private enum Segment: CaseIterable {
        case a, b, c, d, e, f, g
    }

    /// The bars of the digits drawn as a segment display: 2, 3, 4, 5 and 7.
    private static func segments(for digit: Int) -> [Segment] {
        switch digit {
        case 2: [.a, .b, .g, .e, .d]
        case 3: [.a, .b, .g, .c, .d]
        case 4: [.f, .g, .b, .c]
        case 5: [.a, .f, .g, .c, .d]
        default: [.a, .b, .c]
        }
    }

    private static func bar(_ segment: Segment) -> Piece {
        let t = stroke
        let middle = (height - t) / 2
        let half = height / 2 + t / 2
        let rect = switch segment {
        case .a: CGRect(x: 0, y: 0, width: 1, height: t)
        case .g: CGRect(x: 0, y: middle, width: 1, height: t)
        case .d: CGRect(x: 0, y: height - t, width: 1, height: t)
        case .f: CGRect(x: 0, y: 0, width: t, height: half)
        case .b: CGRect(x: 1 - t, y: 0, width: t, height: half)
        case .e: CGRect(x: 0, y: middle, width: t, height: half)
        case .c: CGRect(x: 1 - t, y: middle, width: t, height: half)
        }
        return .rounded(rect, radius: t / 2)
    }

    /// The glyph's outline at a width of 1: its pieces joined into one shape.
    var outline: Path {
        Self.outlines[self] ?? Path()
    }

    private static let outlines: [FlowGlyph: Path] = {
        var outlines: [FlowGlyph: Path] = [.colon: join(FlowGlyph.colon.pieces)]
        for value in 0...9 {
            outlines[.digit(value)] = join(FlowGlyph.digit(value).pieces)
        }
        return outlines
    }()

    private static func join(_ pieces: [Piece]) -> Path {
        pieces.map(\.path).reduce(Path()) { $0.isEmpty ? $1 : $0.union($1) }
    }
}

extension FlowGlyph.Piece {
    var path: Path {
        switch self {
        case .rounded(let rect, let radius):
            Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        case .circle(let center, let radius):
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        case .bowl(let rect, let radius, let thickness):
            Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                .subtracting(Path(roundedRect: rect.insetBy(dx: thickness, dy: thickness),
                                  cornerRadius: max(radius - thickness, 0), style: .continuous))
        }
    }
}

/// A glyph's outline scaled to fill its frame.
struct FlowGlyphShape: Shape {
    let glyph: FlowGlyph

    func path(in rect: CGRect) -> Path {
        let scale = rect.height / FlowGlyph.height
        return glyph.outline.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }
}

/// Where the Flow face draws its time: in one line on a landscape face, with
/// the hours over the minutes and no colon on a portrait one, like HomeView's
/// square face, centered in the room inside the face insets. Sized for the
/// widest time, so the digits keep their size as the hours change, and
/// widgets keep clear of `bounds` (the face's `FaceContentRegion`).
struct FlowClockLayout: Equatable {
    /// A glyph and where it goes at full size, in face points.
    struct Placed: Equatable {
        let glyph: FlowGlyph
        let frame: CGRect
    }

    /// The width of a digit, in points. A digit is `FlowGlyph.height` times as tall.
    let unit: CGFloat
    /// The glyphs drawn, in reading order.
    let placed: [Placed]
    /// The widest time's block, which widgets keep clear of.
    let bounds: CGRect

    /// Lays `glyphs` out on a face of `size` inside `insets`.
    static func make(_ glyphs: [FlowGlyph], size: CGSize, insets: EdgeInsets) -> FlowClockLayout {
        let content = CGRect(x: insets.leading, y: insets.top,
                             width: max(size.width - insets.leading - insets.trailing, 0),
                             height: max(size.height - insets.top - insets.bottom, 0))
        let isStacked = size.height > size.width
        let widest = rows(FlowGlyph.glyphs("00:00"), isStacked: isStacked)
        let widestWidth = widest.map(rowWidth).max() ?? 0
        let widestHeight = blockHeight(rows: widest.count)
        // Room for widgets around it: the top and bottom rows in landscape, and
        // in portrait those and the outer columns.
        let unit = max(min(content.width * (isStacked ? 0.56 : 0.88) / max(widestWidth, 1),
                           content.height * (isStacked ? 0.6 : 0.62) / widestHeight), 0)
        let bounds = CGRect(x: content.midX - widestWidth * unit / 2, y: content.midY - widestHeight * unit / 2,
                            width: widestWidth * unit, height: widestHeight * unit)
        // The time itself, centered in the same block.
        let lines = rows(glyphs, isStacked: isStacked)
        let height = blockHeight(rows: lines.count) * unit
        var placed: [Placed] = []
        for (index, line) in lines.enumerated() {
            let width = rowWidth(line) * unit
            var x = content.midX - width / 2
            let y = content.midY - height / 2 + CGFloat(index) * (FlowGlyph.height + rowGap) * unit
            for glyph in line {
                placed.append(Placed(glyph: glyph,
                                     frame: CGRect(x: x, y: y, width: glyph.width * unit, height: FlowGlyph.height * unit)))
                x += (glyph.width + FlowGlyph.gap) * unit
            }
        }
        return FlowClockLayout(unit: unit, placed: placed, bounds: bounds)
    }

    /// The space between the hours and the minutes when they are stacked.
    static let rowGap: CGFloat = 0.3

    /// One line, or the hours over the minutes without the colon.
    private static func rows(_ glyphs: [FlowGlyph], isStacked: Bool) -> [[FlowGlyph]] {
        guard isStacked, let colon = glyphs.firstIndex(of: .colon) else { return [glyphs] }
        return [Array(glyphs[..<colon]), Array(glyphs[(colon + 1)...])]
    }

    private static func rowWidth(_ row: [FlowGlyph]) -> CGFloat {
        row.map(\.width).reduce(0, +) + CGFloat(max(row.count - 1, 0)) * FlowGlyph.gap
    }

    private static func blockHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * FlowGlyph.height + CGFloat(max(rows - 1, 0)) * rowGap
    }
}
