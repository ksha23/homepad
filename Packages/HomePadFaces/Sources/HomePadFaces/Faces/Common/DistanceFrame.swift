import SwiftUI

extension View {
    /// Lays the view out in its far frame and, up close, shrinks it into its
    /// near frame (`DistanceFit`), as one picture. Only `scaleEffect` and
    /// `position` change, so the move animates smoothly and the text inside
    /// never lays out again. Frames are in the parent's coordinates: put it in
    /// a container that fills the face.
    func distanceFrame(far: CGRect, near: CGRect, isNear: Bool, anchor: UnitPoint = .center) -> some View {
        let target = isNear ? DistanceFit.fitted(far.size, in: near, anchor: anchor) : far
        let scale = far.width > 0 ? target.width / far.width : 1
        return frame(width: far.width, height: far.height)
            .scaleEffect(scale)
            .position(x: target.midX, y: target.midY)
    }

    /// A rounded display font (`Font.display`) whose size animates. Text in a
    /// stack that changes size with the distance grows and shrinks smoothly,
    /// and the stack moves with it, where a plain font change steps.
    func displayFont(_ size: CGFloat, weight: Font.Weight = .semibold, width: Font.Width? = nil) -> some View {
        modifier(AnimatableDisplayFont(size: size, weight: weight, width: width))
    }
}

/// `Font.display` with an animatable size. See `displayFont(_:weight:width:)`.
private struct AnimatableDisplayFont: ViewModifier, Animatable {
    var size: CGFloat
    let weight: Font.Weight
    let width: Font.Width?

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        let font = Font.display(size, weight: weight)
        content.font(width.map { font.width($0) } ?? font)
    }
}

/// How detail that shows only up close comes and goes: it fades in over the
/// last 40 percent of the distance move, once the big fact has mostly made
/// room, and fades out early when someone walks away, before the big fact
/// grows back. Faded in from the start, it showed through the big fact
/// still sitting where the detail lands. It rides the host's
/// `Theme.Motion.proximity`, so the whole change is still one move.
struct ProximityDetailTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(LateOpacity(progress: phase.isIdentity ? 1 : 0))
    }

    /// The detail's opacity at `progress` through the move (0 to 1): none
    /// until 0.6, then rising to full.
    static func opacity(at progress: Double) -> Double {
        min(max((progress - 0.6) / 0.4, 0), 1)
    }
}

extension Transition where Self == ProximityDetailTransition {
    /// Detail that shows only up close. See `ProximityDetailTransition`.
    static var proximityDetail: ProximityDetailTransition { ProximityDetailTransition() }
}

/// `ProximityDetailTransition.opacity(at:)` with an animatable progress.
private struct LateOpacity: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(ProximityDetailTransition.opacity(at: progress))
    }
}
