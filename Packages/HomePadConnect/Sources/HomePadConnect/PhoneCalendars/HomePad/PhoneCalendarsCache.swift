import Foundation
import HomePadCore

/// What a HomePad keeps of one person's phone calendars and lists between
/// visits, so they show the moment the person is recognized and while their
/// phone is asleep, and the changes made here that the phone has not saved yet.
struct PhoneCalendarsIndex: Codable, Equatable, Sendable {
    var deviceName: String
    var calendars: [PhoneCalendar] = []
    var events: [PhoneEvent] = []
    /// The days `events` covers.
    var window: DateInterval?
    var calendarsFetchedAt: Date?
    var lists: [PhoneCalendar] = []
    var reminders: [PhoneReminder] = []
    var remindersFetchedAt: Date?
    /// Changes made on this HomePad, oldest first, until the phone saved them.
    var outbox: [PhoneCalendarWrite] = []

    /// Keeps only the calendars and lists the phone still shares, with their
    /// events, reminders and changes.
    mutating func narrow(toCalendars calendarIDs: Set<String>, lists listIDs: Set<String>) {
        calendars.removeAll { !calendarIDs.contains($0.id) }
        events.removeAll { !calendarIDs.contains($0.calendarID) }
        lists.removeAll { !listIDs.contains($0.id) }
        reminders.removeAll { !listIDs.contains($0.listID) }
        outbox.removeAll { write in
            if let change = write.event { return !calendarIDs.contains(change.fields.calendarID) }
            if let listID = write.listID { return !listIDs.contains(listID) }
            return false
        }
        if calendarIDs.isEmpty {
            window = nil
            calendarsFetchedAt = nil
        }
        if listIDs.isEmpty { remindersFetchedAt = nil }
    }
}

/// A change made on the HomePad to a person's phone calendar or list,
/// kept until the phone saved it or the person discards it.
struct PhoneCalendarWrite: Codable, Equatable, Identifiable, Sendable {
    /// The change's ID, the same the phone saves it under.
    var id: UUID
    var event: CalendarChange?
    /// The occurrence an event change replaces, nil when it adds one.
    var eventID: String?
    var reminder: RemindersChange?
    /// The list a reminder change belongs to.
    var listID: String?
    var state: PhoneWriteStatus.State
    var message: String?
    var createdAt: Date

    var kind: PhoneDataKind { event != nil ? .calendars : .reminders }

    var status: PhoneWriteStatus { PhoneWriteStatus(writeID: id, state: state, message: message) }

    static func adding(_ change: CalendarChange, at date: Date) -> PhoneCalendarWrite {
        PhoneCalendarWrite(id: change.id, event: change, state: .sending, createdAt: date)
    }

    static func changing(_ eventID: String, _ change: CalendarChange, at date: Date) -> PhoneCalendarWrite {
        PhoneCalendarWrite(id: change.id, event: change, eventID: eventID, state: .sending, createdAt: date)
    }

    static func reminder(_ change: RemindersChange, listID: String, at date: Date) -> PhoneCalendarWrite {
        PhoneCalendarWrite(id: change.id, reminder: change, listID: listID, state: .sending, createdAt: date)
    }
}

/// On a HomePad: each person's phone calendars, sealed per member
/// (`SealedMemberFiles`), in one index file with its own key, apart from
/// their photos.
struct PhoneCalendarsCache: Sendable {
    private let files: SealedMemberFiles

    init(directory: URL = PhoneCalendarsCache.defaultDirectory,
         keychain: any SecretStore = KeychainStore(service: "com.ksha23.homepad.phonecalendars", synchronizable: false)) {
        files = SealedMemberFiles(directory: directory, keychain: keychain)
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("HomePadConnect/PhoneCalendars", isDirectory: true)
    }

    func load(member: UUID) -> PhoneCalendarsIndex? {
        guard let plain = files.open("index.sealed", member: member) else { return nil }
        return try? Self.decoder.decode(PhoneCalendarsIndex.self, from: plain)
    }

    @discardableResult
    func save(_ index: PhoneCalendarsIndex, member: UUID) -> Bool {
        guard let plain = try? Self.encoder.encode(index) else { return false }
        return files.seal(plain, as: "index.sealed", member: member)
    }

    /// Removes the member's key and folder.
    func delete(member: UUID) {
        files.delete(member: member)
    }

    /// Removes everyone not in `members`.
    func prune(keeping members: Set<UUID>) {
        files.prune(keeping: members)
    }

    // Dates as plain numbers, so an occurrence's start comes back to the exact second.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
