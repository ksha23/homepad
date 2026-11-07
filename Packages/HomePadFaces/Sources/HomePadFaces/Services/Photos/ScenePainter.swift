import CoreGraphics
import Foundation
import HomePadCore

/// Draws a demo scene into two bitmaps at once: the picture, and a mask that
/// is white wherever a subject shape was drawn. Coordinates are unit
/// fractions of the square canvas with the origin at the top left.
final class ScenePainter {
    let picture: CGContext
    let mask: CGContext
    let side: CGFloat

    init?(side: Int) {
        guard let picture = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let mask = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        self.picture = picture
        self.mask = mask
        self.side = CGFloat(side)
        for context in [picture, mask] {
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
        }
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }

    // MARK: Geometry

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * side, y: y * side) }

    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: x0 * side, y: y0 * side, width: (x1 - x0) * side, height: (y1 - y0) * side)
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { p($0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    func roundedRect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, radius: CGFloat) -> CGPath {
        let r = radius * side
        return CGPath(roundedRect: rect(x0, y0, x1, y1), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    // MARK: Background (picture only)

    /// Fills the whole canvas with a vertical gradient between two heights.
    func sky(_ hexes: [String], from y0: CGFloat = 0, to y1: CGFloat = 1) {
        fill(CGPath(rect: rect(0, 0, 1, 1), transform: nil), gradient: hexes, from: p(0, y0), to: p(0, y1))
    }

    func fill(_ path: CGPath, _ hex: String, alpha: CGFloat = 1, subject: Bool = false) {
        picture.addPath(path)
        picture.setFillColor(Self.color(hex, alpha: alpha))
        picture.fillPath()
        if subject { markSubject(path) }
    }

    func fill(_ path: CGPath, gradient hexes: [String], from start: CGPoint, to end: CGPoint, subject: Bool = false) {
        picture.saveGState()
        picture.addPath(path)
        picture.clip()
        if let gradient = Self.gradient(hexes) {
            picture.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        picture.restoreGState()
        if subject { markSubject(path) }
    }

    func glow(center: CGPoint, radius: CGFloat, hex: String, alpha: CGFloat) {
        let colors = [Self.color(hex, alpha: alpha), Self.color(hex, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        picture.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: radius * side, options: [])
    }

    func stroke(_ path: CGPath, _ hex: String, width: CGFloat, alpha: CGFloat = 1, subject: Bool = false) {
        picture.addPath(path)
        picture.setStrokeColor(Self.color(hex, alpha: alpha))
        picture.setLineWidth(width * side)
        picture.setLineCap(.round)
        picture.strokePath()
        if subject {
            mask.addPath(path)
            mask.setStrokeColor(gray: 1, alpha: 1)
            mask.setLineWidth(width * side)
            mask.setLineCap(.round)
            mask.strokePath()
        }
    }

    // MARK: Subject

    private func markSubject(_ path: CGPath) {
        mask.addPath(path)
        mask.setFillColor(gray: 1, alpha: 1)
        mask.fillPath()
    }

    func images() -> (image: CGImage, mask: CGImage)? {
        guard let image = picture.makeImage(), let maskImage = mask.makeImage() else { return nil }
        return (image, maskImage)
    }

    // MARK: Colors

    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    static func gradient(_ hexes: [String]) -> CGGradient? {
        let locations = hexes.indices.map { CGFloat($0) / CGFloat(max(hexes.count - 1, 1)) }
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: hexes.map { color($0) } as CFArray,
                          locations: locations)
    }
}
