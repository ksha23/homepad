import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Press and hold the face to choose a face, as on Apple Watch and HomeView.
/// It behaves like a long press on a widget on iPadOS:
///
/// - A hold that starts on one of the face's buttons (a Home face tile, a
///   thermostat arrow) opens Faces too, and the button does not fire. A quick
///   tap still presses the button.
/// - A tap gesture under the finger (the face's own tap, a camera tile) gives
///   way once the hold is recognized.
/// - A control that takes the press before the hold is due keeps it, such as
///   a light row's level slider in a Modular widget, which takes it at 0.25 s.
/// - Moving more than 10 points ends the hold, so a swipe to the next face
///   never opens Faces.
///
/// UIKit's long press, because SwiftUI's always gives way to a button: a
/// SwiftUI button claims the touch the moment the finger goes down. This one
/// tracks alongside buttons and cancels them once it is recognized, the way
/// iPadOS cancels a button's touch when a long press menu opens.
struct ChooseFaceGesture: UIGestureRecognizerRepresentable {
    /// How long a still press takes: the same hold that enters Home Screen edit mode.
    static let holdDuration = HomeTileView.editHold

    var isEnabled = true
    let perform: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HoldRecognizer {
        let recognizer = HoldRecognizer()
        recognizer.minimumPressDuration = Self.holdDuration
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: HoldRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: HoldRecognizer, context: Context) {
        guard recognizer.state == .began else { return }
        recognizer.cancelButtons()
        if let view = recognizer.view {
            UIImpactFeedbackGenerator(style: .light, view: view).impactOccurred()
        }
        perform()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Buttons track the press alongside the hold, so a button going down
        /// does not end it. Everything else is exclusive: a control that takes
        /// the press first ends the hold, and the hold ends taps and swipes.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            HoldRecognizer.isButton(otherGestureRecognizer)
        }
    }

    /// A long press that remembers its touch, to cancel the buttons under it.
    final class HoldRecognizer: UILongPressGestureRecognizer {
        private weak var touch: UITouch?

        /// SwiftUI names each button's recognizer after the button ("Button<...>").
        /// Should a later iPadOS name it differently, a hold on a button simply
        /// stays with the button, like any other control.
        static func isButton(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer.name?.hasPrefix("Button<") == true
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if touch == nil { touch = touches.first }
        }

        override func reset() {
            super.reset()
            touch = nil
        }

        /// Cancels the buttons pressed under the hold, so letting go does not
        /// also press them. Turning a recognizer off and on is UIKit's way to
        /// cancel it. Each is put back as it was, so a disabled button stays disabled.
        func cancelButtons() {
            for recognizer in touch?.gestureRecognizers ?? [] where Self.isButton(recognizer) {
                guard recognizer.state == .began || recognizer.state == .changed else { continue }
                let wasEnabled = recognizer.isEnabled
                recognizer.isEnabled = false
                recognizer.isEnabled = wasEnabled
            }
        }
    }
}
