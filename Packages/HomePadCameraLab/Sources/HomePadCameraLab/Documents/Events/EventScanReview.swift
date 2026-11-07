import Foundation
import HomePadCore
import Observation

/// The events found on a scanned page while the person checks them and picks
/// a calendar. Finding them happens on this iPad. Adding them goes through
/// `services.calendar`, to a calendar the person may write to, and needs a
/// recognized member, like every other calendar write.
@MainActor
@Observable
final class EventScanReview: Identifiable {
    enum Phase: Equatable {
        case reviewing
        case reading
        case adding
        case added(Int)
        case failed(String)
    }

    var events: [ScannedEvent] = []
    var calendars: [EventCalendarInfo] = []
    var calendarID: String?
    private(set) var phase: Phase = .reviewing
    /// The provider that read the events, when the person asked one to.
    private(set) var readBy: String?
    /// True once iPadOS said no to calendar access.
    private(set) var accessWasRefused = false
    private(set) var text = ""

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let clock: () -> Date

    init(services: AppServices, clock: @escaping () -> Date = Date.init) {
        self.services = services
        self.clock = clock
    }

    // MARK: Finding

    /// Finds the events in recognized text, on this iPad.
    func load(_ text: String) {
        self.text = text
        events = FlyerEventExtractor(now: clock()).events(in: text)
        readBy = nil
        phase = .reviewing
    }

    /// True when an AI provider is set up, so the person may ask it to read the text instead.
    var canAskAssistant: Bool { services.assistant.isConfigured }
    var assistantName: String { services.assistant.activeProviderName }

    /// Sends only the recognized text to the household's AI provider and
    /// shows what it found. Keeps the events found here when it answers with
    /// nothing usable.
    func readWithAssistant() async {
        guard canAskAssistant, !text.isEmpty else { return }
        phase = .reading
        let name = assistantName
        guard let found = await AssistantEventReader.read(text, with: services.assistant, now: clock()) else {
            phase = .failed("\(name) could not read the page. The events found on this iPad are still here.")
            return
        }
        events = found
        readBy = name
        phase = .reviewing
    }

    /// An empty event to fill in, for a page whose date was not found.
    func addBlankEvent() {
        let calendar = Calendar.current
        let now = clock()
        let start = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        let title = text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        events.append(ScannedEvent(title: title, start: start, end: start.addingTimeInterval(FlyerEventExtractor.defaultLength),
                                   isAllDay: false, location: "", isSelected: true, source: ""))
    }

    // MARK: Calendars

    var isRecognized: Bool { services.household.isPersonalContentUnlocked }
    var hasCalendarAccess: Bool { services.calendar.hasAccess }
    /// Changes when the calendars the person may see change, such as when
    /// someone is recognized, so the list reloads.
    var calendarsKey: String { services.calendar.reloadKey }

    /// The calendars the person at the screen may add to. The one chosen stays
    /// chosen while it is still there, else the first, which is the person's
    /// usual calendar for new events.
    func loadCalendars() async {
        calendars = await services.calendar.writableEventCalendars()
        if !calendars.contains(where: { $0.id == calendarID }) { calendarID = calendars.first?.id }
    }

    func requestCalendarAccess() async {
        accessWasRefused = !(await services.calendar.requestAccess())
        await loadCalendars()
    }

    // MARK: Adding

    var selectedCount: Int { events.filter(\.isSelected).count }

    var canAdd: Bool {
        isRecognized && hasCalendarAccess && calendarID != nil && selectedCount > 0
            && phase != .adding && phase != .reading
    }

    /// Adds the selected events to the chosen calendar and takes them off the
    /// list, so a second tap never adds them twice. Stops at the first error
    /// and leaves the rest to try again.
    func add() async {
        guard isRecognized else {
            phase = .failed("Adding events needs someone HomePad recognizes. Look at the screen so it can see who you are.")
            return
        }
        guard let calendarID else { return }
        phase = .adding
        var added = 0
        for event in events where event.isSelected {
            do {
                try await services.calendar.addEvent(event.draft(calendarID: calendarID))
                events.removeAll { $0.id == event.id }
                added += 1
            } catch {
                phase = .failed(added == 0 ? error.localizedDescription : "Added \(added), then: \(error.localizedDescription)")
                return
            }
        }
        phase = .added(added)
    }
}
