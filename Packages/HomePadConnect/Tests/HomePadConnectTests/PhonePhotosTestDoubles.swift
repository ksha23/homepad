import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// A HomePad and Kyle's iPhone joined in memory for phone visits, after the
/// iPhone linked to Kyle. Every message crosses `MessageCodec` and carries the
/// session it came on, like a sealed session. Both carry photos and
/// calendars, wired as `ConnectRuntime` wires them.
@MainActor
final class PhoneLoop {
    let padServices: AppServices
    let padLink: PeerLink
    let approver: PersonalDeviceApprover
    let visits: PhoneVisitClient
    let client: PhonePhotosClient
    let calendars: PhoneCalendarsClient
    let phoneServices: AppServices
    let phoneLink: PeerLink
    let approvals: ApprovalResponder
    let visitServer: PhoneVisitServer
    let server: PhoneLibraryServer
    let calendarServer: PhoneCalendarServer
    let reader = FakePhoneLibrary()
    let store = FakePhoneCalendars()
    let waker = FakeWaker()
    let window = FakeWindow()
    let pad = PeerDevice(id: "pad-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
    let phoneDevice = PeerDevice(id: "phone-kyle", name: "iPhone", kind: .iPhone, isConnected: true)
    let kyle = HouseholdMember(name: "Kyle", avatar: "🦊", isAdmin: true)
    let sam = HouseholdMember(name: "Sam", avatar: "🐼")
    let padKey = P256.Signing.PrivateKey()
    let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-photos-\(UUID().uuidString)")
    let calendarDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-calendars-\(UUID().uuidString)")
    /// The one sealed session between the two, nil while the phone is away.
    var session: UUID? = UUID()
    private(set) var toPadLog: [PeerMessage] = []
    private(set) var toPhoneLog: [PeerMessage] = []

    init() {
        padServices = AppServices(settings: RemoteLoop.freshSettings())
        padServices.household.add(kyle)
        padServices.household.add(sam)
        padLink = PeerLink(services: padServices)
        padLink.identity = LocalIdentity(deviceID: pad.id, name: pad.name, kind: .homePad)
        approver = PersonalDeviceApprover(services: padServices, link: padLink)
        approver.homePadKey = HomePadKey(padKey)
        visits = PhoneVisitClient(services: padServices, link: padLink, approver: approver)
        calendars = PhoneCalendarsClient(visits: visits)
        client = PhonePhotosClient(visits: visits)
        visits.add(calendars)
        visits.add(client)
        client.cache = PhonePhotosCache(directory: cacheDirectory, keychain: MemorySecrets())
        calendars.cache = PhoneCalendarsCache(directory: calendarDirectory, keychain: MemorySecrets())
        phoneServices = AppServices(settings: RemoteLoop.freshSettings())
        phoneLink = PeerLink(services: phoneServices)
        phoneLink.identity = LocalIdentity(deviceID: phoneDevice.id, name: phoneDevice.name, kind: .iPhone)
        approvals = ApprovalResponder(services: phoneServices, link: phoneLink)
        visitServer = PhoneVisitServer(services: phoneServices, link: phoneLink, approvals: approvals)
        server = PhoneLibraryServer(visit: visitServer)
        calendarServer = PhoneCalendarServer(visit: visitServer)
        visitServer.add(server)
        visitServer.add(calendarServer)

        // Weak, not unowned: a visit's tasks can outlive the test that made
        // the loop, and then find the phone gone rather than crash.
        approver.verifyOwner = { _ in true }
        approver.transmit = { [weak self] message, _ in self?.toPhone(message) }
        approvals.publicKey = { P256.Signing.PrivateKey().publicKey.rawRepresentation }
        approvals.notifications = SilentApprovalNotifications()
        approvals.transmit = { [weak self] message, _ in self?.toPad(message) }
        visits.transmit = { [weak self] message, _ in
            guard let self, session != nil else { throw PeerLinkError.notConnected }
            toPhone(message)
        }
        visits.transmitOnSession = { [weak self] message, _, onSession in
            guard let self, onSession == session else { throw PeerLinkError.notConnected }
            toPhone(message)
        }
        visits.currentSession = { [weak self] _ in self?.session }
        let waker = waker
        visits.makeWaker = { waker }
        visits.openTimeout = 0.5
        visits.replyTimeout = 0.5
        calendars.changeTimeout = 0.5
        server.reader = reader
        calendarServer.store = store
        visitServer.window = window
        visitServer.makeWakeListener = { FakeWakeListener() }
        // Answers go back on the session the request came in on, whoever opened it.
        visitServer.reply = { [weak self] message, peer in self?.toPad(message, session: peer.sessionID) }
        visitServer.transmit = { [weak self] message, _ in
            guard let self, session != nil else { throw PeerLinkError.notConnected }
            toPad(message)
        }

        approver.start()
        approvals.start()
        server.start()
        calendarServer.start()
        visitServer.start()
        client.start()
        calendars.start()
        visits.start()
    }

    func toPad(_ message: PeerMessage, session: UUID? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPadLog.append(received)
        var device = phoneDevice
        device.sessionID = session ?? self.session
        padLink.dispatch(received, from: device)
    }

    func toPhone(_ message: PeerMessage, from device: PeerDevice? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPhoneLog.append(received)
        var device = device ?? pad
        device.sessionID = device.sessionID ?? session
        phoneLink.dispatch(received, from: device)
    }

    func sentToPhone(_ type: PeerMessageType) -> [PeerMessage] { toPhoneLog.filter { $0.type == type } }
    func sentToPad(_ type: PeerMessageType) -> [PeerMessage] { toPadLog.filter { $0.type == type } }

    /// Lets queued tasks run.
    func settle() async {
        for _ in 0..<60 { await Task.yield() }
    }

    /// Waits a little for something that takes a few hops and a detached task.
    func eventually(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await settle()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Links the phone to Kyle, with Kyle at the HomePad.
    func link() async throws {
        await approvals.requestState(of: pad.id)
        await settle()
        let choice = try #require(approvals.states[pad.id]?.members.first { $0.id == kyle.id })
        await approvals.linkMember(choice, on: pad.id)
        await settle()
        await approver.allow(try #require(approver.pendingLinks.first))
        await settle()
    }

    /// Links the phone to Kyle and turns on Show My Photos.
    func linkAndShare() async throws {
        try await link()
        await server.setSharing(true, with: pad.id)
        await settle()
    }

    /// Shares these of the phone's calendars and lists with the HomePad, linking first if needed.
    func shareCalendars(_ calendarIDs: [String] = ["home", "work"], lists listIDs: [String] = ["errands"]) async throws {
        if approvals.linkedMember(on: pad.id) == nil { try await link() }
        for calendar in store.calendars() where calendarIDs.contains(calendar.id) {
            await calendarServer.setShared(true, calendar, kind: .calendars, with: pad.id)
        }
        for list in store.lists() where listIDs.contains(list.id) {
            await calendarServer.setShared(true, list, kind: .reminders, with: pad.id)
        }
        await settle()
    }
}

/// Kyle's library: Recents, Favorites and one album.
@MainActor
final class FakePhoneLibrary: PhoneLibraryReader {
    var hasAccess = true
    let photos = (0..<4).map { PhonePhoto(id: "p\($0)", pixelWidth: 4032, pixelHeight: 3024) }

    func requestAccess() async -> Bool { hasAccess }

    func albums() async -> [PhoneAlbum] {
        [
            PhoneAlbum(id: "phone.recents", title: "Recents", kind: .recents, count: 4, keyPhoto: photos[0]),
            PhoneAlbum(id: "phone.favorites", title: "Favorites", kind: .favorites, count: 1, keyPhoto: photos[2]),
            PhoneAlbum(id: "trip", title: "Trip", kind: .album, count: 2, keyPhoto: photos[1]),
        ]
    }

    func photos(in albumID: String, limit: Int) async -> [PhonePhoto]? {
        switch albumID {
        case "phone.recents": photos
        case "phone.favorites": [photos[2]]
        case "trip": [photos[1], photos[3]]
        default: nil
        }
    }

    func jpeg(for photoID: String, pixels: Int) async -> Data? {
        Data("jpeg \(photoID) \(pixels)".utf8)
    }
}

/// Kyle's calendars: Home (the default), Work and a read-only Holidays, and
/// one list, Errands. Writes follow EventKit's store's rules.
@MainActor
final class FakePhoneCalendars: PhoneCalendarStore {
    var hasEventAccess = true
    var hasReminderAccess = true
    var isEventAccessDenied: Bool { false }
    var isReminderAccessDenied: Bool { false }
    var onChange: (() -> Void)?
    /// Every save fails while true, as if EventKit said no.
    var failsSaves = false
    private(set) var adds = 0
    /// The span the last request for events asked for.
    private(set) var lastRange: DateInterval?
    var savedEvents: [PhoneEvent]
    var savedReminders: [PhoneReminder]

    static let today = Calendar.current.startOfDay(for: Date())

    init() {
        let at = { (day: Int, hour: Int) in Self.today.addingTimeInterval(TimeInterval(day * 86_400 + hour * 3600)) }
        savedEvents = [
            PhoneEvent(id: "e1|0", itemID: "e1", externalID: "x-dentist", calendarID: "home", title: "Dentist", start: at(0, 15), end: at(0, 16)),
            PhoneEvent(id: "e2|0", itemID: "e2", calendarID: "work", title: "Standup", start: at(1, 9), end: at(1, 10)),
        ]
        savedReminders = [PhoneReminder(id: "r1", listID: "errands", title: "Return library books")]
    }

    func requestEventAccess() async -> Bool { hasEventAccess }
    func requestReminderAccess() async -> Bool { hasReminderAccess }

    func calendars() -> [PhoneCalendar] {
        guard hasEventAccess else { return [] }
        return [
            PhoneCalendar(id: "home", title: "Home", colorHex: "#0A84FF", accountName: "iCloud", isDefault: true),
            PhoneCalendar(id: "work", title: "Work", colorHex: "#FF9F0A", accountName: "iCloud"),
            PhoneCalendar(id: "holidays", title: "Holidays", colorHex: "#30D158", allowsModifications: false),
        ]
    }

    func lists() -> [PhoneCalendar] {
        hasReminderAccess ? [PhoneCalendar(id: "errands", title: "Errands", colorHex: "#FF9F0A", isDefault: true)] : []
    }

    func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [PhoneEvent] {
        lastRange = DateInterval(start: start, end: end)
        return savedEvents.filter { calendarIDs.contains($0.calendarID) && $0.start < end && $0.end > start }
    }

    func reminders(in listIDs: Set<String>, completedSince: Date) async -> [PhoneReminder] {
        savedReminders.filter { listIDs.contains($0.listID) }
    }

    func event(itemID: String, start: Date) -> PhoneEvent? {
        savedEvents.first { $0.itemID == itemID && abs($0.start.timeIntervalSince(start)) < 1 }
    }

    func reminder(_ reminderID: String) -> PhoneReminder? { savedReminders.first { $0.id == reminderID } }

    func addEvent(_ fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        try check(fields.calendarID, allowed: allowed)
        adds += 1
        let event = PhoneEvent(id: "added\(adds)|0", itemID: "added\(adds)", calendarID: fields.calendarID, title: fields.title,
                               start: fields.start, end: fields.end, isAllDay: fields.isAllDay, location: fields.location)
        savedEvents.append(event)
        return event
    }

    func updateEvent(itemID: String, occurrenceStart: Date, with fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        guard let at = savedEvents.firstIndex(where: { $0.itemID == itemID && abs($0.start.timeIntervalSince(occurrenceStart)) < 1 }) else {
            throw PhoneChangeFailure.notFound
        }
        guard allowed.contains(savedEvents[at].calendarID) else { throw PhoneChangeFailure.notShared }
        try check(fields.calendarID, allowed: allowed)
        savedEvents[at].title = fields.title
        savedEvents[at].start = fields.start
        savedEvents[at].end = fields.end
        savedEvents[at].calendarID = fields.calendarID
        return savedEvents[at]
    }

    func addReminder(_ fields: PhoneReminderFields, allowed: Set<String>) throws -> PhoneReminder {
        guard allowed.contains(fields.listID) else { throw PhoneChangeFailure.notShared }
        guard !failsSaves else { throw PhoneChangeFailure.saveFailed }
        let reminder = PhoneReminder(id: "added-r\(savedReminders.count)", listID: fields.listID, title: fields.title)
        savedReminders.append(reminder)
        return reminder
    }

    func setCompleted(_ reminderID: String, completed: Bool, allowed: Set<String>) throws -> PhoneReminder {
        guard let at = savedReminders.firstIndex(where: { $0.id == reminderID }) else { throw PhoneChangeFailure.notFound }
        guard allowed.contains(savedReminders[at].listID) else { throw PhoneChangeFailure.notShared }
        guard !failsSaves else { throw PhoneChangeFailure.saveFailed }
        savedReminders[at].isCompleted = completed
        return savedReminders[at]
    }

    private func check(_ calendarID: String, allowed: Set<String>) throws {
        guard allowed.contains(calendarID) else { throw PhoneChangeFailure.notShared }
        guard calendars().first(where: { $0.id == calendarID })?.allowsModifications == true else { throw PhoneChangeFailure.readOnly }
        guard !failsSaves else { throw PhoneChangeFailure.saveFailed }
    }
}

@MainActor
final class FakeWaker: PhoneWaking {
    private(set) var started = false
    private(set) var woken: [Data] = []
    func start() { started = true }
    func stop() { started = false }
    func wake(_ tag: Data) -> Bool {
        woken.append(tag)
        return true
    }
}

@MainActor
final class FakeWindow: BackgroundWindow {
    private(set) var isOpen = false
    var isInBackground: Bool { false }
    func begin() { isOpen = true }
    func end() { isOpen = false }
}

@MainActor
final class FakeWakeListener: WakeListening {
    var onWake: @MainActor () -> Void = {}
    var problem: String? { nil }
    private(set) var tags: [Data] = []
    func listen(tags: [Data]) { self.tags = tags }
    func stop() { tags = [] }
}

/// Keys in memory, so tests never touch the Keychain.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func string(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    @discardableResult
    func set(_ value: String?, for account: String) -> Bool {
        lock.withLock { values[account] = value }
        return true
    }
}
