import EventKit
import EventKitUI
import HomePadUI
import SwiftUI

/// Apple's event editor (`EKEventEditViewController`) for adding and editing
/// events. Present it in a `.sheet` with `.systemSheetStyle()`.
struct EventEditorSheet: UIViewControllerRepresentable {
    /// Wraps an event so it can drive `.sheet(item:)`.
    struct Request: Identifiable {
        let id = UUID()
        let event: EKEvent
    }

    let store: EKEventStore
    let event: EKEvent
    /// Called with true when the event was saved or deleted.
    let onFinish: (_ changed: Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action != .canceled)
        }
    }
}
