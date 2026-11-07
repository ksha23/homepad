import CoreText
import HomePadUI
import SwiftUI
import UIKit

/// A line of text as glyph outlines, at a font size of 1, laid out the way
/// `Text` lays out one line: the baseline the font's ascender below the top.
/// `GlyphLineShape` draws it at any size.
struct GlyphLine: Equatable {
    /// The outlines, origin at the start of the baseline, y down.
    let path: CGPath
    /// The line's advance width.
    let advance: CGFloat
    /// From the top of the line to the baseline.
    let ascender: CGFloat
    /// The height of the line of type.
    let lineHeight: CGFloat

    /// The outlines of `text` in `font`, scaled to a font size of 1.
    init(_ text: String, font: UIFont) {
        let size = max(font.pointSize, 1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let outlines = CGMutablePath()
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            // The run's own font, which may be a fallback for a character the font lacks.
            let runFont = attributes[kCTFontAttributeName].map { $0 as! CTFont } ?? (font as CTFont)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                // Font outlines run y up. Flip them and scale to a size of 1.
                var transform = CGAffineTransform(scaleX: 1 / size, y: -1 / size)
                    .translatedBy(x: positions[index].x, y: positions[index].y)
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) {
                    outlines.addPath(glyph)
                }
            }
        }
        // Glyphs are often drawn as overlapping contours, such as a 9's bowl
        // and stem. Joined into one outline, the bevel runs only along the
        // edge and not along the lines inside where they overlap.
        path = outlines.normalized()
        advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / size
        ascender = font.ascender / size
        lineHeight = font.lineHeight / size
    }

    static func == (lhs: GlyphLine, rhs: GlyphLine) -> Bool {
        lhs.path == rhs.path && lhs.advance == rhs.advance && lhs.lineHeight == rhs.lineHeight
    }
}

/// A `GlyphLine` drawn to fill its frame like a line of `Text`: as tall as
/// the frame's height, centered across it, and smaller only when it would
/// not fit the width.
struct GlyphLineShape: Shape {
    let line: GlyphLine

    func path(in rect: CGRect) -> Path {
        guard line.lineHeight > 0, line.advance > 0 else { return Path() }
        let size = min(rect.height / line.lineHeight, rect.width / line.advance)
        let top = rect.midY - line.lineHeight * size / 2
        let transform = CGAffineTransform(translationX: rect.midX - line.advance * size / 2, y: top + line.ascender * size)
            .scaledBy(x: size, y: size)
        return Path(line.path).applying(transform)
    }
}

/// Numerals drawn as frosted glass, like HomeView's Photos time and Weather
/// temperature: the picture behind shows through a light frost tinted with
/// `tint`, a bright bevel runs inside every stroke, and a soft shadow falls
/// outside it. It fills its frame like a line of `Text`.
///
/// Nothing in it moves on its own. The frost redraws only when the picture
/// behind it does (the Photos face's Ken Burns move, the Weather sky), and
/// holds still with it. The bevel and the shadow are drawn once.
struct GlassNumerals: View {
    let line: GlyphLine
    let tint: Color

    var body: some View {
        let shape = GlyphLineShape(line: line)
        ZStack {
            OuterShadow(shape: shape)
            // The frost: the picture behind, blurred and lightened, then tinted.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                tint.opacity(0.3)
            }
            .mask { shape }
            Bevel(shape: shape)
        }
    }
}

/// A light edge inside each stroke, brighter at the top as if lit from
/// above, over a soft glow that gives the strokes some depth.
private struct Bevel: View {
    let shape: GlyphLineShape

    var body: some View {
        ZStack {
            shape.stroke(.white.opacity(0.35), lineWidth: 14)
                .blur(radius: 6)
            shape.stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.45)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 3.2)
        }
        // Only the inside of the strokes.
        .mask { shape }
        .drawingGroup()
    }
}

/// The numerals' drop shadow, outside the strokes only, so it never darkens
/// the glass. Drawn once.
private struct OuterShadow: View {
    let shape: GlyphLineShape

    private static let radius: CGFloat = 24
    private static let drop: CGFloat = 10

    var body: some View {
        // Room around the numerals, so the shadow is not cut off at the layer's edge.
        let room = Self.radius * 2 + Self.drop
        shape.fill(.black)
            .shadow(color: .black.opacity(0.22), radius: Self.radius, y: Self.drop)
            .mask {
                Rectangle().padding(-room)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .padding(room)
            .drawingGroup()
            .padding(-room)
    }
}
