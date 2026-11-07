import CoreGraphics
import HomePadUI

/// Where the photo goes as the full-screen viewer closes.
struct PhotoLanding: Equatable {
    enum Kind: Equatable {
        /// Onto its thumbnail, which takes over in the same place once it lands.
        case thumbnail
        /// The thumbnail is off screen: to the nearest place on screen at the
        /// thumbnail's size, fading out on the way.
        case nearest
        /// No thumbnail to go to (a slideshow, or a grid that has not laid the
        /// photo out): straight down and off the screen.
        case away
    }

    /// In the viewer's coordinates.
    var rect: CGRect
    var kind: Kind
}

/// Where the viewer's photo sits while it is pulled down and where it lands,
/// as plain values for tests. Rectangles are in the viewer's own coordinates,
/// which cover the whole screen and never scale or move, so a thumbnail's
/// frame measured once as the viewer closes stays the place it lands.
enum PhotoViewerGeometry {
    /// The photo at `rect` pulled `translation` by a finger: it moves with the
    /// finger, gives only a little above where the drag started, and shrinks
    /// about its center as it goes down (`SwipeDismissPolicy`).
    static func pulled(_ rect: CGRect, by translation: CGSize, policy: SwipeDismissPolicy) -> CGRect {
        let scale = policy.scale(for: translation.height)
        let width = rect.width * scale
        let height = rect.height * scale
        let midX = rect.midX + translation.width
        let midY = rect.midY + policy.offset(for: translation.height)
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }

    /// Where a photo at `rect` lands for a thumbnail at `thumbnail`, on a
    /// screen of `bounds`. All three are in the viewer's coordinates.
    static func landing(thumbnail: CGRect?, from rect: CGRect, in bounds: CGRect) -> PhotoLanding {
        guard let thumbnail, !thumbnail.isEmpty else {
            let drop = max(0, bounds.maxY - rect.minY)
            return PhotoLanding(rect: rect.offsetBy(dx: 0, dy: drop), kind: .away)
        }
        if thumbnail.intersects(bounds) {
            return PhotoLanding(rect: thumbnail, kind: .thumbnail)
        }
        let x = min(max(thumbnail.minX, bounds.minX), bounds.maxX - thumbnail.width)
        let y = min(max(thumbnail.minY, bounds.minY), bounds.maxY - thumbnail.height)
        return PhotoLanding(rect: CGRect(origin: CGPoint(x: x, y: y), size: thumbnail.size), kind: .nearest)
    }

    /// The finger's release speed (points per second) as the initial velocity
    /// of a spring that takes the photo from `start` to `end`: the part of the
    /// speed along that way, as the share of the way covered per second. The
    /// photo carries on at the finger's speed instead of stopping when it is
    /// let go. Released moving away from `end`, it first carries on away.
    static func springVelocity(_ velocity: CGSize, from start: CGRect, to end: CGRect) -> Double {
        let dx = end.midX - start.midX
        let dy = end.midY - start.midY
        let squaredDistance = dx * dx + dy * dy
        guard squaredDistance > 1 else { return 0 }
        let share = (velocity.width * dx + velocity.height * dy) / squaredDistance
        return Double(max(-20, min(20, share)))
    }
}
