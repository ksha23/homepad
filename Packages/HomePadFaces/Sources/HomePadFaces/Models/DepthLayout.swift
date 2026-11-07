import CoreGraphics
import Foundation

/// Whether the Photos face's time can sit behind the subject, and how a
/// place on the screen maps into the photo.
enum DepthLayout {
    /// Maps a normalized view rect to the normalized image rect it shows when
    /// the image fills the view (aspect fill, centered).
    static func imageRect(forViewRect rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let shown = CGSize(width: viewSize.width / scale, height: viewSize.height / scale)
        let origin = CGPoint(x: (imageSize.width - shown.width) / 2, y: (imageSize.height - shown.height) / 2)
        return CGRect(
            x: (origin.x + rect.minX * shown.width) / imageSize.width,
            y: (origin.y + rect.minY * shown.height) / imageSize.height,
            width: rect.width * shown.width / imageSize.width,
            height: rect.height * shown.height / imageSize.height
        )
    }

    /// The time goes behind the subject only when there is a subject and it
    /// hides less than about a third of the numerals. Otherwise it stays in
    /// front. At 45 percent a cactus over the centered time left "9:38"
    /// reading as one digit.
    static func usesDepth(timeCoverage: Double, subjectCoverage: Double) -> Bool {
        subjectCoverage > 0.01 && timeCoverage < 0.35
    }
}
