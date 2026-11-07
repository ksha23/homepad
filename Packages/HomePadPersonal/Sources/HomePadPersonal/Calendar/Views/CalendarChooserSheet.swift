import EventKit
import EventKitUI
import HomePadUI
import SwiftUI

/// Apple's calendar chooser (`EKCalendarChooser`) in multiple-selection mode.
/// Settings uses it to pick which calendars or reminders lists belong to one
/// member, or to everyone. Present it in a `.sheet` with `.systemSheetStyle()`.
struct CalendarChooserSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let entityType: EKEntityType
    let title: String
    let selectedIDs: Set<String>
    /// Called with the chosen identifiers, or nil when cancelled.
    let onFinish: (Set<String>?) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let chooser = EKCalendarChooser(selectionStyle: .multiple, displayStyle: .allCalendars, entityType: entityType, eventStore: store)
        chooser.title = title
        chooser.showsDoneButton = true
        chooser.showsCancelButton = true
        chooser.selectedCalendars = Set(selectedIDs.compactMap { store.calendar(withIdentifier: $0) })
        chooser.delegate = context.coordinator
        return UINavigationController(rootViewController: chooser)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKCalendarChooserDelegate {
        let onFinish: (Set<String>?) -> Void

        init(onFinish: @escaping (Set<String>?) -> Void) {
            self.onFinish = onFinish
        }

        func calendarChooserDidFinish(_ chooser: EKCalendarChooser) {
            onFinish(Set(chooser.selectedCalendars.map(\.calendarIdentifier)))
        }

        func calendarChooserDidCancel(_ chooser: EKCalendarChooser) {
            onFinish(nil)
        }
    }
}
