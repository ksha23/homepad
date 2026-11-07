import Foundation
import HomePadCore

/// Reminders through the same privacy filter as calendars.
extension HouseholdCalendarService {
    /// The list other modules add to when they name none ("add milk").
    public var defaultListName: String { settings[PersonalSettings.defaultReminderList] }

    /// The default list, when the viewer may see it. Matched by name, ignoring
    /// case, among the iPad's lists: it is the household's, never a list on
    /// someone's phone that happens to share its name.
    public var defaultList: CalendarSource? {
        let name = defaultListName
        return visibleReminderLists.first { $0.phone == nil && $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Visible reminders, optionally limited to one list, from the iPad's
    /// lists and the recognized person's own phone.
    public func reminderItems(listID: String? = nil, includeCompleted: Bool = false) async -> [ReminderItem] {
        let visible = visibleReminderLists.filter { listID == nil || $0.id == listID }
        guard !visible.isEmpty else { return [] }
        let own = Set(visible.filter { $0.phone == nil }.map(\.id))
        let onIPad = backend.hasReminderAccess && !own.isEmpty ? await backend.reminders(listIDs: own, includeCompleted: includeCompleted) : []
        let onPhone = phoneReminderItems(listIDs: Set(visible.filter { $0.phone != nil }.map(\.id)), includeCompleted: includeCompleted)
        return (onIPad + onPhone).sorted(by: Self.reminderOrder)
    }

    public func reminders(includeCompleted: Bool) async -> [CalendarItem] {
        let shared = Set(visibleReminderLists.filter(isShared).map(\.id))
        return await reminderItems(includeCompleted: includeCompleted).map { reminder in
            var item = reminder.calendarItem
            item.isShared = shared.contains(reminder.listID)
            return item
        }
    }

    public func reminderLists() async -> [ReminderListInfo] {
        visibleReminderLists.map { list in
            ReminderListInfo(id: list.id, title: list.title, colorHex: list.colorHex, isShared: isShared(list))
        }
    }

    public func setReminderCompleted(id: String, completed: Bool) async throws {
        try setCompleted(try await visibleReminder(id), completed)
    }

    /// Removes a reminder from a visible list (used to undo a scanned grocery item).
    /// Reminders on someone's phone are only added and checked off from here.
    public func removeReminder(id: String) async throws {
        let reminder = try await visibleReminder(id)
        if let phone = reminder.phoneDeviceName { throw UnsupportedOperation("Removing a reminder on \(phone)") }
        try backend.removeReminder(reminderID: id)
        changeToken += 1
    }

    private func visibleReminder(_ id: String) async throws -> ReminderItem {
        guard let reminder = await reminderItems(includeCompleted: true).first(where: { $0.id == id }) else {
            throw PersonalError.reminderNotFound(id)
        }
        return reminder
    }

    /// Adds a reminder. A nil `listName` uses the default list (Groceries out of the box),
    /// which is created and shared with everyone if it does not exist yet. A
    /// name only the recognized person's phone has goes to that phone.
    public func addReminder(title: String, due: Date?, listName: String?) async throws {
        if let listName, !visibleReminderLists.contains(where: { $0.phone == nil && Self.named($0, listName) }),
           let onPhone = phoneReminderLists.first(where: { Self.named($0, listName) }) {
            try phoneService().addReminder(title: title, due: due, listID: onPhone.id)
            return
        }
        guard backend.hasReminderAccess else { throw PersonalError.noReminderAccess }
        let list = try await list(named: listName ?? defaultListName, createIfMissing: listName == nil || listName == defaultListName)
        _ = try backend.addReminder(title: title, due: due, listID: list.id)
        changeToken += 1
    }

    /// Adds a reminder to a list the viewer can see. One on their own phone is sent there.
    public func addReminder(title: String, toListID listID: String) throws {
        guard let list = visibleReminderLists.first(where: { $0.id == listID }) else { throw PersonalError.notVisible }
        if list.phone != nil { return try phoneService().addReminder(title: title, due: nil, listID: listID) }
        _ = try backend.addReminder(title: title, due: nil, listID: listID)
        changeToken += 1
    }

    /// Checks a reminder off (or back on). Only reminders in visible lists.
    public func setCompleted(_ reminder: ReminderItem, _ completed: Bool) throws {
        guard let list = visibleReminderLists.first(where: { $0.id == reminder.listID }) else { throw PersonalError.notVisible }
        if list.phone != nil { return try phoneService().setReminderCompleted(reminder.id, completed: completed) }
        try backend.setCompleted(reminderID: reminder.id, completed: completed)
        changeToken += 1
    }

    /// Creates a list. Its audience follows the unassigned policy until someone assigns it.
    @discardableResult
    public func createList(named name: String) throws -> CalendarSource {
        let list = try backend.createReminderList(named: name)
        changeToken += 1
        return list
    }

    /// Makes sure the default list exists, so other modules can always add groceries.
    func ensureDefaultList() async {
        guard backend.hasReminderAccess else { return }
        _ = try? await list(named: defaultListName, createIfMissing: true)
    }

    /// Finds one of the iPad's visible lists by name, case-insensitively.
    /// Creating the default list also marks it as shared with everyone.
    func list(named name: String, createIfMissing: Bool) async throws -> CalendarSource {
        if let match = visibleReminderLists.first(where: { $0.phone == nil && Self.named($0, name) }) {
            return match
        }
        if backend.reminderLists().contains(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            throw PersonalError.notVisible
        }
        guard createIfMissing else { throw PersonalError.listNotFound(name) }
        let created = try backend.createReminderList(named: name)
        settings[PersonalSettings.calendarAudiences][created.id] = .everyone
        changeToken += 1
        return created
    }

    nonisolated static func named(_ list: CalendarSource, _ name: String) -> Bool {
        list.title.localizedCaseInsensitiveCompare(name) == .orderedSame
    }

    /// Open first, then by due date (undated last), then by title.
    nonisolated static func reminderOrder(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }
}
