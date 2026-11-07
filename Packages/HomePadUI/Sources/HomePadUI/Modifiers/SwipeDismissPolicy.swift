import CoreGraphics

/// The axis a drag moves along, decided by its first movement.
public enum DragAxis: Sendable {
    case horizontal, vertical
}

/// The decisions behind swiping down to close a full-screen surface, as plain
/// values so they can be tested: when a drag may start, how the surface follows
/// the finger, and whether letting go closes it or springs it back.
///
/// `.swipeDownToDismiss(isEnabled:onDismiss:)` uses the standard values. A
/// surface that draws its own close, like the Photos viewer shrinking back into
/// its thumbnail, uses the same values so every surface feels the same.
public struct SwipeDismissPolicy: Equatable, Sendable {
    /// How far down a release closes, whatever its speed. Music's first swipe
    /// down closed at 140 points.
    public var closeDistance: CGFloat = 140
    /// A downward flick at least this fast, in points per second, closes from a shorter pull.
    public var flickVelocity: CGFloat = 700
    /// A flick still travels this far first, so the jitter of a tap never closes anything.
    public var minimumFlickDistance: CGFloat = 24
    /// Drags that start this close to the top or bottom of the window belong to
    /// the shell's edge gestures (Control Center, the assistant, going Home).
    public var edgeZone: CGFloat = 44
    /// How small the surface gets once pulled `fadeDistance` down.
    public var minimumScale: CGFloat = 0.9
    /// The pull over which the backdrop fades out and the surface shrinks to `minimumScale`.
    public var fadeDistance: CGFloat = 420
    /// How much of a pull back up, past where the drag started, the surface follows.
    public var upwardResistance: CGFloat = 0.15

    public init() {}

    /// The values every surface uses.
    public static let standard = SwipeDismissPolicy()

    // MARK: Starting

    /// The axis a drag moves along: horizontal when it moved more across than
    /// down or up, vertical when it moved more down or up. Nil before it moves,
    /// and for an exact diagonal, which belongs to neither.
    public static func axis(of translation: CGSize) -> DragAxis? {
        let across = abs(translation.width), along = abs(translation.height)
        if across > along { return .horizontal }
        if along > across { return .vertical }
        return nil
    }

    /// True when a drag starting at `startY` (window points) began in the bands
    /// the shell keeps for its edge swipes.
    public func startsInEdgeZone(startY: CGFloat, windowHeight: CGFloat) -> Bool {
        startY < edgeZone || startY > windowHeight - edgeZone
    }

    /// Whether a drag may start closing the surface: it starts away from the
    /// window's top and bottom edges, it moves down more than sideways, and any
    /// scrolling content under the finger is already at its top, so the pull
    /// past the top closes it as an iPadOS sheet does.
    public func shouldBegin(startY: CGFloat, windowHeight: CGFloat, translation: CGSize, isScrolledToTop: Bool) -> Bool {
        guard !startsInEdgeZone(startY: startY, windowHeight: windowHeight) else { return false }
        guard Self.axis(of: translation) == .vertical, translation.height > 0 else { return false }
        return isScrolledToTop
    }

    // MARK: Following the finger

    /// How far the surface moves for a finger `translation` points below where
    /// it started. Above the start it gives only a little.
    public func offset(for translation: CGFloat) -> CGFloat {
        translation >= 0 ? translation : translation * upwardResistance
    }

    /// 0 at rest, 1 once pulled `fadeDistance` down.
    public func progress(for translation: CGFloat) -> CGFloat {
        min(1, max(0, translation / fadeDistance))
    }

    /// The surface's scale, shrinking a little as it is pulled down.
    public func scale(for translation: CGFloat) -> CGFloat {
        1 - (1 - minimumScale) * progress(for: translation)
    }

    /// How opaque the backdrop is. It fades as the surface is pulled, so what
    /// the surface covers shows through.
    public func backdropOpacity(for translation: CGFloat) -> Double {
        Double(1 - progress(for: translation))
    }

    /// With Reduce Motion the surface stays put and fades instead, reaching
    /// half its opacity at the close distance.
    public func reducedMotionOpacity(for translation: CGFloat) -> Double {
        Double(1 - 0.5 * min(1, max(0, translation / closeDistance)))
    }

    // MARK: Letting go

    /// Whether letting go closes the surface: a quick flick down, or a pull past
    /// `closeDistance` that was not flicked back up. Otherwise it springs back.
    public func shouldClose(translation: CGFloat, velocity: CGFloat) -> Bool {
        if velocity <= -flickVelocity { return false }
        if velocity >= flickVelocity, translation >= minimumFlickDistance { return true }
        return translation >= closeDistance
    }

    /// The release speed as a spring's initial velocity: the share of the
    /// distance left to travel covered per second, so the surface carries on at
    /// the finger's speed instead of stopping when it is let go.
    public static func relativeVelocity(_ velocity: CGFloat, from start: CGFloat, to end: CGFloat) -> Double {
        let distance = end - start
        guard abs(distance) > 1 else { return 0 }
        return Double(max(-20, min(20, velocity / distance)))
    }
}
