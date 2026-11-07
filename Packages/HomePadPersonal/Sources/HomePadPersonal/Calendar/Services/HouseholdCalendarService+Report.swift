import EventKit
import Foundation

/// A plain text report of every calendar HomePad can see, whether it shows and
/// why, for finding a missing calendar on a device. Launching with
/// `-HomePadCalendarReport YES` writes it to the app's Documents folder, where
/// `xcrun devicectl device copy from` can fetch it.
extension HouseholdCalendarService {
    func diagnosticReport(now: Date = Date()) -> String {
        let viewer = viewer
        let end = now.addingTimeInterval(14 * 24 * 3600)
        var lines = [
            "HomePad calendar report \(now.formatted(.iso8601))",
            "Event access: \(Self.accessName(EKEventStore.authorizationStatus(for: .event)))",
            "Demo data: \(isUsingDemoData)",
            "Household: \(household.members.count) people, \(viewer.adminIDs.count) admins, "
                + "someone selected: \(viewer.memberID != nil), unlocked: \(viewer.isUnlocked)",
            "Calendars nobody chose: \(settings[PersonalSettings.unassignedCalendars])",
            "",
        ]
        let sources = allSources(.events)
        lines.append("\(sources.count) calendars:")
        for source in sources {
            let status = status(of: source)
            let count = backend.events(from: now, to: end, calendarIDs: [source.id]).count
            lines.append("- \(source.title) | account \(source.accountName ?? "none") | type \(source.calendarType.rawValue) "
                + "| audience \(status.audience) | origin \(status.origin) | shows now \(status.isVisibleNow) "
                + "| checked in Calendars \(isShown(source)) "
                + "| events in the next 14 days \(count)")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the report after the calendars load, when the launch argument asks for it.
    func writeDiagnosticReportIfAsked() {
        guard PersonalDebugLaunch.writesCalendarReport else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            try? self.diagnosticReport().write(to: folder.appendingPathComponent("calendar-report.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static func accessName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "full access"
        case .writeOnly: "add events only"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "unknown"
        }
    }
}
