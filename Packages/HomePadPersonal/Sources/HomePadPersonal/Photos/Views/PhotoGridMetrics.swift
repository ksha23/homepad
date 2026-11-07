import CoreGraphics
import HomePadUI

/// The sizes the Photos app draws album covers and grid thumbnails at. Photo
/// sync prepares pictures at the same sizes, since PhotoKit's cache serves a
/// request only at the size it was prepared for.
enum PhotoGridMetrics {
    /// The narrowest a thumbnail in an album's grid gets.
    static let minimumThumbnail: CGFloat = 200
    static var spacing: CGFloat { Theme.Spacing.xs }
    /// Pixels a grid thumbnail asks PhotoKit for, enough for a 200 point cell on a 2x screen.
    static let thumbnailPixels = CGSize(width: 400, height: 400)
    /// Pixels an album cover asks for.
    static let coverPixels = CGSize(width: 600, height: 600)

    /// How many thumbnails the first screen of an album's grid holds on a
    /// screen of `size`, in whichever orientation holds more.
    static func firstScreenCount(on size: CGSize) -> Int {
        max(count(width: size.width, height: size.height), count(width: size.height, height: size.width))
    }

    private static func count(width: CGFloat, height: CGFloat) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let columns = max(1, Int((width + spacing) / (minimumThumbnail + spacing)))
        let side = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let rows = Int((height / (side + spacing)).rounded(.up))
        return columns * rows
    }
}
