import Foundation

/// What the right-hand side of the Reminders app shows.
enum ReminderFilter: Hashable {
    case today
    case scheduled
    case all
    case list(CalendarSource)

    var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .all: "All"
        case .list(let list): list.title
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar.circle.fill"
        case .scheduled: "calendar.badge.clock"
        case .all: "tray.full.fill"
        case .list(let list): ReminderFilter.icon(forListTitle: list.title)
        }
    }

    var colorHex: String {
        switch self {
        case .today: "#0A84FF"
        case .scheduled: "#FF453A"
        case .all: "#8E8E93"
        case .list(let list): list.colorHex
        }
    }

    /// Whether a reminder belongs in this view.
    func includes(_ item: ReminderItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            guard let due = item.due else { return false }
            return calendar.isDate(due, inSameDayAs: now) || item.isOverdue(now: now, calendar: calendar)
        case .scheduled: return item.due != nil
        case .all: return true
        case .list(let list): return item.listID == list.id
        }
    }

    /// Smart lists show which list each reminder came from.
    var showsListName: Bool {
        if case .list = self { return false }
        return true
    }

    /// Friendly icons for common list names, like the Reminders app's list glyphs.
    static func icon(forListTitle title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("grocer") || lowered.contains("shop") { return "cart.fill" }
        if lowered.contains("errand") { return "car.fill" }
        if lowered.contains("home") || lowered.contains("house") || lowered.contains("chore") { return "house.fill" }
        if lowered.contains("work") { return "briefcase.fill" }
        if lowered.contains("gift") { return "gift.fill" }
        if lowered.contains("health") || lowered.contains("wellness") { return "figure.run" }
        return "list.bullet"
    }
}
