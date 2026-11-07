import CoreGraphics

/// How the full-screen Photos viewer pages, as plain values for tests: where a
/// page sits while a finger drags it, where a release settles, and which pages
/// to have ready so a swipe never shows a photo still loading.
///
/// A position is a page index, fractional mid-drag: 2.25 is a quarter of the
/// way from the third photo to the fourth.
enum PhotoPaging {
    /// The black gap between pages, as in the Photos app.
    static let gap: CGFloat = 24
    /// A release at least this fast, in points per second, turns the page.
    static let flickVelocity: CGFloat = 400
    /// A flick still has to move the page this far.
    static let minimumFlickDistance: CGFloat = 16
    /// A slower release turns the page once it moved this share of a page.
    static let turnFraction: CGFloat = 0.5
    /// Past the first or last photo a page follows only this share of the drag.
    static let edgeResistance: CGFloat = 0.3

    /// The position for a finger `translation` points across (negative is
    /// left, toward the next photo) from page `index`. Past either end the
    /// page gives a little and no more.
    static func position(from index: Int, translation: CGFloat, pageWidth: CGFloat, count: Int) -> CGFloat {
        guard pageWidth > 0, count > 0 else { return CGFloat(index) }
        let position = CGFloat(index) - translation / (pageWidth + gap)
        let last = CGFloat(count - 1)
        if position < 0 { return position * edgeResistance }
        if position > last { return last + (position - last) * edgeResistance }
        return position
    }

    /// The page a release settles on: the next or previous one after a flick
    /// or a drag past half a page, otherwise the one it started on. A flick
    /// against the drag goes back. Never more than one page, never past the ends.
    static func target(from index: Int, translation: CGFloat, velocity: CGFloat, pageWidth: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var step = 0
        let flicked = abs(translation) >= minimumFlickDistance
        if flicked, velocity <= -flickVelocity {
            step = 1
        } else if flicked, velocity >= flickVelocity {
            step = -1
        } else if translation <= -pageWidth * turnFraction {
            step = 1
        } else if translation >= pageWidth * turnFraction {
            step = -1
        }
        return min(max(0, index + step), count - 1)
    }

    /// The pages to draw: those on screen at `position` and one more on each
    /// side, so the next photo is already loaded when a swipe reveals it.
    static func window(around position: CGFloat, count: Int) -> ClosedRange<Int> {
        guard count > 0 else { return 0...0 }
        let lower = max(0, Int(position.rounded(.down)) - 1)
        let upper = min(count - 1, Int(position.rounded(.up)) + 1)
        return min(lower, upper)...upper
    }

    /// Pages to load into the image cache beyond the drawn ones, for quick swipes.
    static func prefetch(around index: Int, count: Int) -> [Int] {
        [index - 2, index + 2].filter { (0..<count).contains($0) }
    }

    /// Where a page sits across the screen at `position`.
    static func offset(of page: Int, at position: CGFloat, pageWidth: CGFloat) -> CGFloat {
        (CGFloat(page) - position) * (pageWidth + gap)
    }

    /// A photo of `aspectRatio` (width over height) as large as it fits, centered.
    static func fittedRect(aspectRatio: CGFloat, in size: CGSize) -> CGRect {
        guard aspectRatio > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        var width = size.width
        var height = width / aspectRatio
        if height > size.height {
            height = size.height
            width = height * aspectRatio
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The page a slideshow shows next, back to the first after the last.
    static func nextInSlideshow(after index: Int, count: Int) -> Int {
        count > 0 ? (index + 1) % count : 0
    }
}
