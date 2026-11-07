import Foundation

/// Calendars of one account for the Calendars list, in the order Apple's
/// Calendar app uses: iCloud, other accounts, subscribed calendars, then Other
/// (holidays and birthdays). Pure, so tests can check the order.
public struct CalendarAccountGroup: Identifiable, Equatable, Sendable {
    public var title: String
    public var calendars: [CalendarSource]

    public var id: String { title }

    public static func groups(_ sources: [CalendarSource]) -> [CalendarAccountGroup] {
        let byTitle = Dictionary(grouping: sources, by: title(for:))
        return byTitle.keys
            .sorted { (rank($0), $0.localizedLowercase) < (rank($1), $1.localizedLowercase) }
            .map { title in
                let calendars = byTitle[title, default: []].sorted { $0.title.localizedLowercase < $1.title.localizedLowercase }
                return CalendarAccountGroup(title: title, calendars: calendars)
            }
    }

    /// The account name EventKit gives, such as "iCloud", "Gmail" or "Subscribed Calendars".
    static func title(for source: CalendarSource) -> String {
        source.accountName ?? source.calendarType.label ?? "Other"
    }

    private static func rank(_ title: String) -> Int {
        let lowered = title.lowercased()
        if lowered == "icloud" { return 0 }
        if lowered.contains("subscribed") { return 2 }
        if lowered == "other" { return 3 }
        return 1
    }
}
