import CoreGraphics
import HomePadUI

/// The decisions behind swiping Music's mini player sideways to skip, as plain
/// values so they can be tested: how far the cover and title follow the
/// finger, and whether letting go plays the next song, the one before or
/// neither.
///
/// A swipe left plays the next song and a swipe right the one before, as in
/// Apple Music's mini player and CarPlay's Now Playing bar. A flick is as fast
/// as the one that closes a full-screen surface (`SwipeDismissPolicy`), so
/// every swipe in HomePad takes the same flick.
struct MiniPlayerSwipe: Equatable, Sendable {
    /// Which song a swipe plays.
    enum Skip: Equatable, Sendable {
        case next, previous
    }

    /// How far a release skips, whatever its speed: a comfortable tap target's
    /// width, well past the jitter of a tap.
    var skipDistance: CGFloat = Theme.Size.tapTarget
    /// A flick at least this fast, in points per second, skips from a shorter drag.
    var flickVelocity: CGFloat = SwipeDismissPolicy.standard.flickVelocity
    /// A flick still travels this far first, so the jitter of a tap never skips.
    var minimumFlickDistance: CGFloat = SwipeDismissPolicy.standard.minimumFlickDistance
    /// How far the cover and title can move. They come close, never all the way.
    var travel: CGFloat = Theme.Size.tapTarget
    /// The share of the finger's first movement the cover and title follow.
    /// Farther along they give less and less, as a scroll view stretches past
    /// its end.
    var resistance: CGFloat = 0.5
    /// How faint the cover and title get as they near `travel`.
    var minimumOpacity = 0.4

    /// The values the mini player uses.
    static let standard = MiniPlayerSwipe()

    // MARK: Following the finger

    /// How far the cover and title move for a finger `translation` points
    /// along: half as far at first, then less and less, never past `travel`.
    func offset(for translation: CGFloat) -> CGFloat {
        let distance = travel * (1 - 1 / (1 + stretch(translation)))
        return translation < 0 ? -distance : distance
    }

    /// How opaque the cover and title are. They fade a little as they move, so
    /// the title passing the buttons stays quiet.
    func opacity(for translation: CGFloat) -> Double {
        let progress = abs(offset(for: translation)) / travel
        return 1 - (1 - minimumOpacity) * Double(progress)
    }

    /// How fast the cover and title move, in points per second, while the
    /// finger moves at `velocity` with `translation` behind it: half its speed
    /// at first, slower the farther they are stretched.
    func offsetVelocity(_ velocity: CGFloat, at translation: CGFloat) -> CGFloat {
        let stretch = stretch(translation)
        return velocity * resistance / ((1 + stretch) * (1 + stretch))
    }

    private func stretch(_ translation: CGFloat) -> CGFloat {
        resistance * abs(translation) / travel
    }

    // MARK: Letting go

    /// What letting go plays: a drag past `skipDistance`, or a quick flick,
    /// skips the way it went. Left is the next song, right the one before. A
    /// short slow drag, or one flicked back the way it came, skips nothing.
    func skip(translation: CGFloat, velocity: CGFloat) -> Skip? {
        guard translation != 0 else { return nil }
        let skip: Skip = translation < 0 ? .next : .previous
        // The release speed along the drag, below zero when flicked back.
        let speed = translation < 0 ? -velocity : velocity
        if speed <= -flickVelocity { return nil }
        if speed >= flickVelocity, abs(translation) >= minimumFlickDistance { return skip }
        return abs(translation) >= skipDistance ? skip : nil
    }
}
