import Foundation
import HomePadCore
import Testing
@testable import HomePadCameraLab

/// Scanned flyers, invitations and school letters turned into events on the
/// iPad, the optional assistant reading, and adding through the calendar
/// service. The fixtures are text as the document camera reads such pages.
@MainActor
@Suite struct FlyerEventTests {
    private let calendar = Calendar.current

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A moment in the iPad's own time zone, as the detector reads dates.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func events(_ name: String, today: Date) throws -> [ScannedEvent] {
        FlyerEventExtractor(now: today, calendar: calendar).events(in: try fixture(name))
    }

    // MARK: On the iPad

    @Test func aFlyerGetsItsHeadlineTimesAndThePlaceAboveTheAddress() throws {
        let found = try events("flyer-bake-sale", today: date(2026, 3, 10, 9))
        #expect(found.count == 1)
        let sale = try #require(found.first)
        #expect(sale.title == "Spring Bake Sale")
        #expect(sale.start == date(2026, 4, 18, 10))
        #expect(sale.end == date(2026, 4, 18, 14))
        #expect(!sale.isAllDay)
        #expect(sale.location == "Lincoln Elementary School Gym, 1234 Maple Ave, Madison, WI 53711")
        #expect(sale.isSelected)
    }

    @Test func anInvitationUsesItsLabelsAndKeepsTheRSVPUnselected() throws {
        let found = try events("flyer-birthday-invitation", today: date(2026, 3, 10, 9))
        #expect(found.map(\.title) == ["RSVP for Maya's 7th Birthday Party", "Maya's 7th Birthday Party"])
        let rsvp = found[0]
        #expect(rsvp.isAllDay)
        #expect(rsvp.start == date(2026, 4, 26))
        #expect(!rsvp.isSelected)
        let party = found[1]
        #expect(party.start == date(2026, 5, 3, 14))
        #expect(party.end == date(2026, 5, 3, 16, 30))
        #expect(party.location == "Westside Park Pavilion, 2002 Regent St")
        #expect(party.isSelected)
    }

    @Test func aLetterTakesItsTitleFromTheSentenceAndItsTimesFromTheNextOnes() throws {
        let found = try events("flyer-school-letter", today: date(2026, 9, 20, 9))
        #expect(found.map(\.title) == ["Permission slips due", "Second grade class will visit the Henry Vilas Zoo"])
        // The detector skips a date right after "due" unless it is masked.
        let slips = found[0]
        #expect(slips.start == date(2026, 10, 5))
        #expect(slips.isAllDay)
        #expect(!slips.isSelected)
        let trip = found[1]
        #expect(trip.start == date(2026, 10, 9, 9, 15))
        #expect(trip.end == date(2026, 10, 9, 14, 30))
    }

    @Test func aListOfDatesGivesAnEventPerLine() throws {
        let found = try events("flyer-school-dates", today: date(2026, 8, 20, 9))
        #expect(found.map(\.title) == ["Picture Day", "Back to School Night", "Parent-Teacher Conferences", "No School", "Winter Concert"])
        #expect(found[0].isAllDay && found[0].start == date(2026, 9, 17))
        #expect(found[1].start == date(2026, 9, 24, 18, 30))
        #expect(found[1].end == date(2026, 9, 24, 19, 30))
        // "October 22-23" spans both days.
        #expect(found[2].isAllDay)
        #expect(found[2].start == date(2026, 10, 22))
        #expect(found[2].end == date(2026, 10, 23))
        #expect(found[3].start == date(2026, 11, 27))
        #expect(found[4].start == date(2026, 12, 10, 19))
        #expect(found[4].location == "The auditorium")
    }

    @Test func daysWithoutAYearAndWeekdaysAloneAreTheNextOnes() {
        let thursday = date(2026, 11, 5, 9)
        let extractor = FlyerEventExtractor(now: thursday, calendar: calendar)
        let movie = extractor.events(in: "Movie night Friday at 6")
        #expect(movie.map(\.title) == ["Movie night"])
        #expect(movie.first?.start == date(2026, 11, 6, 18))
        // March has passed this year, so it is next March.
        #expect(extractor.events(in: "Book fair 3/14").first?.start == date(2027, 3, 14))
        #expect(extractor.events(in: "Nothing to see here.").isEmpty)
    }

    @Test func anAllDayDraftEndsOnItsLastDay() {
        let event = ScannedEvent(title: " Conferences ", start: date(2026, 10, 22), end: date(2026, 10, 23), isAllDay: true,
                                 location: "  ", isSelected: true, source: "")
        let draft = event.draft(calendarID: "family", calendar: calendar)
        #expect(draft.title == "Conferences")
        #expect(draft.isAllDay)
        #expect(draft.start == date(2026, 10, 22))
        #expect(calendar.isDate(draft.end, inSameDayAs: date(2026, 10, 23)))
        #expect(draft.location == nil)
        #expect(draft.calendarID == "family")
    }

    // MARK: The assistant

    @Test func theAssistantGetsOnlyTheTextAsASelfContainedTask() async throws {
        let assistant = RecordingAssistant(reply: """
            ```json
            {"events": [
              {"title": "Maya's 7th Birthday Party", "date": "2026-05-03", "startTime": "14:00", "endTime": "16:30",
               "endDate": null, "location": "Westside Park Pavilion, 2002 Regent St", "isDeadline": false},
              {"title": "RSVP for Maya's party", "date": "2026-04-26", "startTime": null, "endTime": null,
               "endDate": null, "location": "Jen", "isDeadline": true}
            ]}
            ```
            """)
        let text = try fixture("flyer-birthday-invitation")
        let found = try #require(await AssistantEventReader.read(text, with: assistant, now: date(2026, 3, 10, 9), calendar: calendar))
        let request = try #require(assistant.requests.first)
        #expect(request.isSelfContained)
        #expect(request.images.isEmpty)
        #expect(!request.speakResponse && !request.presentInOverlay)
        #expect(request.text.contains(text))
        #expect(request.text.contains("Today is Tuesday, March 10, 2026 (2026-03-10)."))

        #expect(found.map(\.title) == ["Maya's 7th Birthday Party", "RSVP for Maya's party"])
        #expect(found[0].start == date(2026, 5, 3, 14))
        #expect(found[0].end == date(2026, 5, 3, 16, 30))
        #expect(found[1].isAllDay && !found[1].isSelected && found[1].location.isEmpty)
    }

    @Test func anUnusableReplyKeepsNothingAndAnEmptyOneMeansNoEvents() {
        #expect(AssistantEventReader.decode("Sorry, I cannot help with that.") == nil)
        #expect(AssistantEventReader.decode(#"{"events": []}"#)?.isEmpty == true)
        #expect(AssistantEventReader.decode(#"{"events": [{"title": "", "date": "2026-05-03"}]}"#)?.isEmpty == true)
    }

    // MARK: Adding

    @Test func addingNeedsARecognizedPersonAndUsesTheChosenCalendar() async throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "test.cameralab.events.\(UUID())")!))
        let calendarService = RecordingCalendar()
        services.calendar = calendarService
        let review = EventScanReview(services: services, clock: { date(2026, 3, 10, 9) })
        review.load(try fixture("flyer-birthday-invitation"))
        await review.loadCalendars()
        #expect(review.calendarID == "family")
        #expect(review.selectedCount == 1)

        // Nobody recognized: nothing is written.
        #expect(!review.canAdd)
        await review.add()
        #expect(calendarService.drafts.isEmpty)

        let alex = HouseholdMember(name: "Alex", avatar: "🦊", colorHex: "#FF9500", isAdmin: true)
        _ = services.household.add(alex)
        services.household.recognize(alex.id)
        review.calendarID = "alex"
        #expect(review.canAdd)
        await review.add()
        #expect(review.phase == .added(1))
        let draft = try #require(calendarService.drafts.first)
        #expect(draft.title == "Maya's 7th Birthday Party")
        #expect(draft.calendarID == "alex")
        #expect(draft.location == "Westside Park Pavilion, 2002 Regent St")
        // Added events leave the list, so a second tap cannot add them twice.
        #expect(review.events.map(\.title) == ["RSVP for Maya's 7th Birthday Party"])
    }
}

/// Answers every request with one reply and keeps the requests.
@MainActor
private final class RecordingAssistant: AssistantService {
    var phase: AssistantPhase = .idle
    var liveTranscript = ""
    var activeProviderName = "Claude"
    var isConfigured: Bool { true }
    private(set) var requests: [AssistantRequest] = []
    private let reply: String

    init(reply: String) {
        self.reply = reply
    }

    func ask(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        requests.append(request)
        let reply = reply
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(reply))
            continuation.yield(.finished(fullText: reply))
            continuation.finish()
        }
    }

    func startListening() {}
    func stopListening() {}
    func cancel() {}
}

/// Two calendars to add to, recording the events added.
@MainActor
private final class RecordingCalendar: CalendarService {
    private(set) var drafts: [EventDraft] = []

    var hasAccess: Bool { true }
    func requestAccess() async -> Bool { true }
    func events(from start: Date, to end: Date) async -> [CalendarItem] { [] }
    func reminders(includeCompleted: Bool) async -> [CalendarItem] { [] }
    func addReminder(title: String, due: Date?, listName: String?) async throws {}
    func addEvent(title: String, start: Date, end: Date) async throws {}

    func writableEventCalendars() async -> [EventCalendarInfo] {
        [EventCalendarInfo(id: "family", title: "Family", isShared: true), EventCalendarInfo(id: "alex", title: "Alex")]
    }

    func addEvent(_ draft: EventDraft) async throws {
        drafts.append(draft)
    }
}
