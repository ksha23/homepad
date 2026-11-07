#if os(iOS)
import SwiftUI
import UIKit

/// Which drags a `DirectionalPan` takes.
public enum PanDirection: Sendable {
    /// Drags whose first movement is down: swiping a surface away.
    case down
    /// Drags whose first movement is sideways: paging.
    case horizontal
}

/// A one-finger pan that takes a drag only when its first movement goes its way,
/// so a pager and a swipe down on the same surface never fight: each drag locks
/// to the axis it starts along.
///
/// A downward pan also leaves alone what an iPadOS sheet leaves alone:
/// - drags that start in the window's top and bottom bands, which belong to the
///   shell's edge swipes (`SwipeDismissPolicy.edgeZone`)
/// - drags that start on a UIKit control, such as a slider or the system volume
///   slider. SwiftUI controls with a drag of their own (`BigSlider`, a scrubber)
///   keep it too, because SwiftUI gives a view's own gesture precedence over
///   one on the view around it
/// - pulls inside scrolling content that is not at its top. Scroll views wait
///   for the pan, so at the top a pull down moves the surface instead of
///   bouncing the content, and anywhere else it scrolls.
///
/// Built on UIKit because only a UIKit recognizer can see the scroll views and
/// controls under the finger. Most surfaces use `.swipeDownToDismiss(isEnabled:onDismiss:)`,
/// which is built on it.
public struct DirectionalPan: UIGestureRecognizerRepresentable {
    public var direction: PanDirection
    public var isEnabled: Bool
    public var policy: SwipeDismissPolicy
    /// The finger's travel since the drag started, in points.
    public var onChanged: (CGSize) -> Void
    /// The travel and the release speed in points per second. A cancelled drag
    /// ends with zero for both.
    public var onEnded: (_ translation: CGSize, _ velocity: CGSize) -> Void

    public init(
        _ direction: PanDirection, isEnabled: Bool = true, policy: SwipeDismissPolicy = .standard,
        onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (_ translation: CGSize, _ velocity: CGSize) -> Void
    ) {
        self.direction = direction
        self.isEnabled = isEnabled
        self.policy = policy
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    public func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    public func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        context.coordinator.configure(self)
        return pan
    }

    public func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.configure(self)
        // Turned off mid-drag: cancel it, so the surface springs back.
        if !isEnabled, recognizer.state == .began || recognizer.state == .changed {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    public func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // Global space: stable while the surface under the finger moves with it.
        let translation = context.converter.translation(in: .global) ?? .zero
        let velocity = context.converter.velocity(in: .global) ?? .zero
        switch recognizer.state {
        case .began, .changed:
            onChanged(CGSize(width: translation.x, height: translation.y))
        case .ended:
            onEnded(CGSize(width: translation.x, height: translation.y), CGSize(width: velocity.x, height: velocity.y))
        case .cancelled, .failed:
            onEnded(.zero, .zero)
        default:
            break
        }
    }

    /// Decides, for UIKit, which touches and drags the pan takes.
    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var direction = PanDirection.down
        private var isEnabled = true
        private var policy = SwipeDismissPolicy.standard
        /// The touch the drag started with, to find the scroll views under it.
        private weak var touch: UITouch?
        /// Where it touched down, in window points.
        private var start: CGPoint = .zero
        private var windowHeight: CGFloat = 0

        func configure(_ pan: DirectionalPan) {
            direction = pan.direction
            isEnabled = pan.isEnabled
            policy = pan.policy
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            if let view = touch.view, Self.isOnControl(view, below: gestureRecognizer.view) { return false }
            self.touch = touch
            start = touch.location(in: nil)
            windowHeight = touch.window?.bounds.height ?? 0
            return true
        }

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let movement = Self.movement(of: pan, since: start)
            switch direction {
            case .horizontal:
                return SwipeDismissPolicy.axis(of: movement) == .horizontal
            case .down:
                return policy.shouldBegin(startY: start.y, windowHeight: windowHeight, translation: movement,
                                          isScrolledToTop: isScrolledToTop(within: pan.view))
            }
        }

        /// How far the finger has moved since it touched down. The pan's own
        /// translation is still zero here, since UIKit counts it from where the
        /// pan begins, and a slow drag would look as if it had not moved. The
        /// speed stands in if the finger is somehow back where it started.
        private static func movement(of pan: UIPanGestureRecognizer, since start: CGPoint) -> CGSize {
            let now = pan.location(in: nil)
            let moved = CGSize(width: now.x - start.x, height: now.y - start.y)
            guard moved == .zero else { return moved }
            let velocity = pan.velocity(in: nil)
            return CGSize(width: velocity.x, height: velocity.y)
        }

        /// Scroll views inside wait for a downward pan, so a pull past the top
        /// moves the surface and nothing else. The pan fails at once for any
        /// other drag, and then they scroll as usual.
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard direction == .down, let scrollView = other.view as? UIScrollView,
                  other === scrollView.panGestureRecognizer, let view = gestureRecognizer.view else { return false }
            return scrollView.isDescendant(of: view)
        }

        /// True when every scroll view under the touch that scrolls vertically
        /// shows the top of its content.
        private func isScrolledToTop(within root: UIView?) -> Bool {
            var scrollViews = (touch?.gestureRecognizers ?? []).compactMap { recognizer -> UIScrollView? in
                guard let scrollView = recognizer.view as? UIScrollView, recognizer === scrollView.panGestureRecognizer else { return nil }
                return scrollView
            }
            var view = touch?.view
            while let current = view, current !== root {
                if let scrollView = current as? UIScrollView { scrollViews.append(scrollView) }
                view = current.superview
            }
            return scrollViews.allSatisfy { scrollView in
                let inset = scrollView.adjustedContentInset
                let scrollsVertically = scrollView.contentSize.height + inset.top + inset.bottom > scrollView.bounds.height + 1
                return !scrollsVertically || scrollView.contentOffset.y <= -inset.top + 1
            }
        }

        /// True for a touch on a UIKit control (a slider, a switch, the system
        /// volume slider, the AirPlay button) or in text, which keep their drags.
        private static func isOnControl(_ view: UIView, below root: UIView?) -> Bool {
            var current: UIView? = view
            while let candidate = current, candidate !== root {
                if candidate is UIControl || candidate is UITextView { return true }
                current = candidate.superview
            }
            return false
        }
    }
}
#endif
