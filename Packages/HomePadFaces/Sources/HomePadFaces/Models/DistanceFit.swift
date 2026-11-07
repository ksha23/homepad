import CoreGraphics
import SwiftUI

/// Where a part of a face that is drawn at its far size goes up close: the
/// same picture shrunk to fit its near frame. Faces draw text that shows at
/// both distances once, at the far size, and shrink it with `scaleEffect`, so
/// walking up moves it in one glide. A new font size would lay the text out
/// again and jump.
enum DistanceFit {
    /// The scale that fits `size` inside `bounds`. Never above 1: text shrunk
    /// from its far size stays sharp, text blown up past it would blur.
    static func scale(_ size: CGSize, into bounds: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(min(bounds.width / size.width, bounds.height / size.height, 1), 0)
    }

    /// The frame a view of `size` takes once scaled to fit `rect`, placed in
    /// `rect` at `anchor` (top leading keeps it in the rect's top leading corner).
    static func fitted(_ size: CGSize, in rect: CGRect, anchor: UnitPoint = .center) -> CGRect {
        let scale = scale(size, into: rect.size)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.minX + (rect.width - fitted.width) * anchor.x,
                      y: rect.minY + (rect.height - fitted.height) * anchor.y,
                      width: fitted.width, height: fitted.height)
    }
}
