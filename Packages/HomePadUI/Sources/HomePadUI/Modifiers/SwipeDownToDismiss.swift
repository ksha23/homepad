#if os(iOS)
import HomePadCore
import SwiftUI

/// `-HomePadSwipeTrace YES` writes Documents/swipe-trace.txt: each swipe down's start, release,
/// close and landing, so a surface that stays open, or will not open again, can be followed on a
/// device. Screens that present such a surface log their own opens and closes into it.
@MainActor
public enum SwipeTrace {
    public static let trace = DebugTrace(file: "swipe-trace.txt", argument: "HomePadSwipeTrace")
}

/// How a surface looks while it is swiped down.
public enum SwipeDismissStyle: Sendable {
    /// A full-screen surface, such as a camera: it follows the finger as a card
    /// that shrinks a little and rounds its corners, and the black backdrop
    /// behind it fades so the screen it covers shows through. Its content
    /// moves and shrinks through `.fullScreenSurfaceContent()`.
    case fullScreen
    /// A panel over a dimmed screen, such as Play On: it only follows the finger.
    case panel
}

/// True while a surface is being swiped down or is settling, so what it covers
/// can show through. The shell reads it to show the app that opened Now Playing.
public struct SwipeDismissIsPulledKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

public extension View {
    /// Closes this surface with a swipe down, as iPadOS closes sheets, the Music
    /// player and the Photos viewer. The surface follows the finger, and letting
    /// go past `SwipeDismissPolicy.closeDistance`, or with a quick flick, slides
    /// it away and calls `onDismiss`. A shorter pull springs back. With Reduce
    /// Motion it fades instead of moving.
    ///
    /// A full-screen surface moves and shrinks as one card, as on iPadOS, with
    /// its page's color reaching the card's rounded edges, the shell's margin
    /// included. The page itself never moves or scales. SwiftUI gives a view
    /// under a scale other than 1 no safe area, and a view moved down none at
    /// its top, so a page background that ignores the safe area would stop
    /// short of the card's edges for as long as the pull lasts. The page stays
    /// where it is, the card's outline moves and shrinks over it as a clip, and
    /// the content moves and shrinks with the card. Put
    /// `.fullScreenSurfaceContent()` on the content, inside the page, and keep
    /// the page a plain color, since a picture there would stay still inside
    /// the moving card.
    ///
    /// Edge swipes, drags on sliders and other controls, and pulls in content
    /// that is not scrolled to its top never close it (see `DirectionalPan`).
    /// VoiceOver's escape gesture closes it too.
    ///
    /// Once swiped away, the surface stays off the screen and ignores touches
    /// while its removal transition runs. Give each opening its own identity,
    /// such as `.id` with a count of closings, so a surface opened again in that
    /// moment is a new view. Otherwise the closing view comes back as it was,
    /// off the screen, and every later opening shows nothing.
    ///
    ///     ZStack {
    ///         Color.black.ignoresSafeArea()
    ///         controls.fullScreenSurfaceContent()
    ///     }
    ///     .swipeDownToDismiss(onDismiss: onClose)
    ///
    /// - Parameters:
    ///   - isEnabled: False while something on the surface needs vertical drags.
    ///   - style: `.fullScreen` for a surface that covers the screen, `.panel` for a panel.
    ///   - onDismiss: Closes the surface. Called once it has slid away.
    func swipeDownToDismiss(isEnabled: Bool = true, style: SwipeDismissStyle = .fullScreen, onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeDownToDismissModifier(isEnabled: isEnabled, style: style, onDismiss: onDismiss))
    }
}

private struct SwipeDownToDismissModifier: ViewModifier {
    let isEnabled: Bool
    let style: SwipeDismissStyle
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the finger has moved down since the drag started.
    @State private var pull: CGFloat = 0
    /// From the drag's first movement until the surface has settled or closed.
    @State private var isPulled = false
    @State private var isClosing = false
    /// The surface's frame and the screen's, in global coordinates.
    @State private var frame: CGRect = .zero
    @State private var screen: CGRect = .zero

    private var policy: SwipeDismissPolicy { .standard }
    private var moves: Bool { !reduceMotion }
    private var isFullScreen: Bool { style == .fullScreen }

    /// How far the surface has moved down.
    private var drop: CGFloat {
        moves ? policy.offset(for: pull) : 0
    }

    /// The card's scale, below 1 while a full-screen surface is pulled down.
    private var cardScale: CGFloat {
        isFullScreen && moves ? policy.scale(for: pull) : 1
    }

    /// How far the card reaches past the surface's frame. While pulled, to the
    /// screen's edges, where its page's background reaches past the safe area.
    /// At rest, and for a panel, so far that it clips nothing.
    private var clipOutset: EdgeInsets {
        guard isFullScreen, isPulled, !screen.isEmpty else {
            return EdgeInsets(top: 4096, leading: 4096, bottom: 4096, trailing: 4096)
        }
        return EdgeInsets(top: max(0, frame.minY - screen.minY), leading: max(0, frame.minX - screen.minX),
                          bottom: max(0, screen.maxY - frame.maxY), trailing: max(0, screen.maxX - frame.maxX))
    }

    func body(content: Content) -> some View {
        content
            // A full-screen surface's content moves and shrinks with the card
            // (`.fullScreenSurfaceContent()`).
            .transformEnvironment(\.fullScreenSurfaceScale) { $0 *= cardScale }
            .transformEnvironment(\.fullScreenSurfaceOffset) { $0 += isFullScreen ? drop : 0 }
            // Its page stays where it is, so its background keeps reaching
            // past the safe area, and only the card's outline moves and shrinks
            // over it: the screen's edges, scaled like the content, carried
            // down with the finger, its corners rounding as it goes.
            .clipShape(OutsetRoundedRectangle(
                cornerRadius: isFullScreen && moves ? Theme.Radius.tile * policy.progress(for: pull) : 0, outset: clipOutset)
                .scale(cardScale)
                .offset(y: isFullScreen ? drop : 0))
            // A panel has no page, and moves itself.
            .offset(y: isFullScreen ? 0 : drop)
            .opacity(moves ? 1 : policy.reducedMotionOpacity(for: pull))
            .background {
                Color.black
                    .opacity(isFullScreen ? backdropOpacity : 0)
                    // Measured inside `ignoresSafeArea()`, where the backdrop
                    // has the screen's size. Outside it, it has the surface's.
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { screen = $0 }
                    .ignoresSafeArea()
            }
            .gesture(DirectionalPan(.down, isEnabled: isEnabled && !isClosing, policy: policy, onChanged: { translation in
                if !isPulled { SwipeTrace.trace.log("pull starts, closing \(isClosing)") }
                isPulled = true
                pull = translation.height
            }, onEnded: release))
            .preference(key: SwipeDismissIsPulledKey.self, value: isPulled)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame = $0 }
            .accessibilityAction(.escape) { onDismiss() }
            // Once it is leaving, touches go to what it uncovers. Its backdrop
            // stays, almost clear, until the slide finishes, and would otherwise
            // take a tap meant for what is under it, such as Music's mini player.
            .allowsHitTesting(!isClosing)
    }

    private var backdropOpacity: Double {
        moves ? policy.backdropOpacity(for: pull) : policy.reducedMotionOpacity(for: pull)
    }

    private func release(translation: CGSize, velocity: CGSize) {
        let closes = policy.shouldClose(translation: translation.height, velocity: velocity.height)
        SwipeTrace.trace.log("release pull \(Int(pull)) velocity \(Int(velocity.height)), \(closes ? "closes" : "springs back")")
        if closes {
            close(velocity: velocity.height)
        } else {
            let spring = Animation.interpolatingSpring(
                Theme.Motion.settleSpring,
                initialVelocity: SwipeDismissPolicy.relativeVelocity(velocity.height, from: pull, to: 0))
            withAnimation(spring) {
                pull = 0
            } completion: {
                SwipeTrace.trace.log("sprang back, pull \(Int(pull))")
                if pull == 0 { isPulled = false }
            }
        }
    }

    /// Slides the surface off the bottom (or fades it), then closes it. It stays
    /// there, so a removal transition starts from where it went.
    private func close(velocity: CGFloat) {
        isClosing = true
        // A whole screen down, so the surface and any background reaching past
        // its safe area into the screen's top margin are gone. Stopping when
        // the frame's top reached the bottom left that margin showing as a strip,
        // which then vanished at once.
        let end = moves ? max(screen.height, frame.height) : policy.closeDistance * 2
        let animation: Animation = moves
            ? .interpolatingSpring(Theme.Motion.settleSpring,
                                   initialVelocity: SwipeDismissPolicy.relativeVelocity(velocity, from: pull, to: end))
            : Theme.Motion.standard
        SwipeTrace.trace.log("close from \(Int(pull)) to \(Int(end))")
        withAnimation(animation) {
            pull = end
        } completion: {
            SwipeTrace.trace.log("closed, dismissing")
            onDismiss()
        }
    }
}

/// A rounded rectangle drawn outside the view's frame by `outset`, so a clip
/// can reach backgrounds that ignore the safe area.
private struct OutsetRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    var outset: EdgeInsets

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outer = CGRect(x: rect.minX - outset.leading, y: rect.minY - outset.top,
                           width: rect.width + outset.leading + outset.trailing,
                           height: rect.height + outset.top + outset.bottom)
        return Path(roundedRect: outer, cornerRadius: cornerRadius, style: .continuous)
    }
}
#endif
