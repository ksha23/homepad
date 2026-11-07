import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reports every touch that starts anywhere in the window, without taking
/// touches away from the views underneath (buttons, scroll views, sheets).
/// The kiosk uses it to know someone is using the screen, and Now Playing to
/// bring its controls back.
public struct TouchObserver: UIViewRepresentable {
    let onTouch: () -> Void
    let onTouchAt: ((CGPoint) -> Void)?

    /// - Parameters:
    ///   - onTouch: Called on every touch-down.
    ///   - at: Also called with where it went down, in window coordinates.
    public init(onTouch: @escaping () -> Void, at onTouchAt: ((CGPoint) -> Void)? = nil) {
        self.onTouch = onTouch
        self.onTouchAt = onTouchAt
    }

    public func makeUIView(context: Context) -> TouchObserverView {
        let view = TouchObserverView(onTouch: onTouch)
        view.recognizer.onTouchAt = onTouchAt
        return view
    }

    public func updateUIView(_ view: TouchObserverView, context: Context) {
        view.recognizer.onTouch = onTouch
        view.recognizer.onTouchAt = onTouchAt
    }
}

/// An invisible view that attaches a passive recognizer to its window.
public final class TouchObserverView: UIView {
    let recognizer = PassiveTouchRecognizer()

    init(onTouch: @escaping () -> Void) {
        super.init(frame: .zero)
        recognizer.onTouch = onTouch
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer.view?.removeGestureRecognizer(recognizer)
        window?.addGestureRecognizer(recognizer)
    }
}

/// Fires on touch-down and then fails at once, so it never blocks or delays
/// any other gesture.
final class PassiveTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouch: (() -> Void)?
    /// Where the touch went down, in window coordinates.
    var onTouchAt: ((CGPoint) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch?()
        if let onTouchAt, let point = touches.first?.location(in: nil) { onTouchAt(point) }
        if SwipeTrace.trace.isEnabled, let point = touches.first?.location(in: nil) {
            SwipeTrace.trace.log("touch down at \(Int(point.x)),\(Int(point.y)), \(touches.count) touches, \(event.allTouches?.count ?? 0) on screen")
        }
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
