import CoreGraphics
import Foundation

/// A small grayscale copy of a subject mask, for fast coverage questions.
struct MaskSample: Sendable, Equatable {
    let width: Int
    let height: Int
    /// Row-major, 0 is background and 255 is subject.
    let values: [UInt8]

    /// Fraction of a normalized rect (0...1 in both axes) covered by the subject.
    func coverage(in rect: CGRect) -> Double {
        guard width > 0, height > 0 else { return 0 }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return 0 }
        let x0 = Int((clipped.minX * CGFloat(width)).rounded(.down))
        let x1 = max(Int((clipped.maxX * CGFloat(width)).rounded(.up)), x0 + 1)
        let y0 = Int((clipped.minY * CGFloat(height)).rounded(.down))
        let y1 = max(Int((clipped.maxY * CGFloat(height)).rounded(.up)), y0 + 1)
        var total = 0
        var count = 0
        for y in y0..<min(y1, height) {
            for x in x0..<min(x1, width) {
                total += Int(values[y * width + x])
                count += 1
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count * 255)
    }

    /// The normalized bounding box of the subject, or nil when there is none.
    var subjectBounds: CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where values[y * width + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width), height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
