import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// Records system alarm calls and can pretend one was stopped outside the app.
@MainActor
final class RecordingRings: AlarmRingScheduling {
    var scheduled: [UUID: Date] = [:]
    var cancelled: [UUID] = []
    var dismissedOutside: Set<UUID> = []
    func schedule(_ alarm: HomeAlarm, at date: Date) { scheduled[alarm.id] = date }
    func cancel(_ id: UUID) { cancelled.append(id); scheduled[id] = nil }
    func wasDismissedOutsideApp(_ id: UUID) -> Bool { dismissedOutside.contains(id) }
}

/// The household's members, changed by hand.
@MainActor
final class MemberList {
    var ids: Set<UUID>
    init(ids: Set<UUID>) { self.ids = ids }
}

/// The test clock starts on Friday 15 January 2027 at 8:00 in UTC.
@MainActor
@Suite struct AlarmServiceTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "alarm-tests-\(UUID().uuidString)")
    let clock = TestClock()
    let rings = RecordingRings()
    let events = EventBus()
    let owner = UUID()

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var store: AlarmStateStore { AlarmStateStore(fileURL: directory.appending(path: "alarms.json")) }

    private func makeService() -> AlarmService {
        let clock = clock
        return AlarmService(store: store, events: events, rings: rings, clock: { clock.now }, calendar: Self.utc)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    private var wakeCount: Int {
        events.recent.filter { if case .wake = $0.1 { return true } else { return false } }.count
    }

    // MARK: Next ring

    @Test func aOneTimeAlarmRingsTodayOrTomorrow() {
        let later = HomeAlarm(ownerID: owner, hour: 9, minute: 30)
        let earlier = HomeAlarm(ownerID: owner, hour: 7, minute: 0)
        #expect(later.nextOccurrence(after: clock.now, calendar: Self.utc) == at(15, 9, 30))
        #expect(earlier.nextOccurrence(after: clock.now, calendar: Self.utc) == at(16, 7))
    }

    /// Friday 8:00: a weekday 7:00 alarm next rings on Monday.
    @Test func aWeekdayAlarmSkipsTheWeekend() {
        let alarm = HomeAlarm(ownerID: owner, hour: 7, minute: 0, weekdays: Locale.Weekday.workweek)
        #expect(alarm.nextOccurrence(after: clock.now, calendar: Self.utc) == at(18, 7))
        let weekend = HomeAlarm(ownerID: owner, hour: 9, minute: 0, weekdays: Locale.Weekday.weekend)
        #expect(weekend.nextOccurrence(after: clock.now, calendar: Self.utc) == at(16, 9))
    }

    // MARK: Ringing

    @Test func addingAnAlarmSetsItsNextRingAndTheSystemAlarm() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 9, minute: 0))
        #expect(service.upcoming[alarm.id] == at(15, 9))
        #expect(rings.scheduled[alarm.id] == at(15, 9))
        #expect(service.nextRing(ownedBy: owner)?.alarm.id == alarm.id)
        #expect(service.nextRing(ownedBy: UUID()) == nil)
    }

    @Test func itRingsInTheAppAtItsTimeAndCancelsTheSystemAlarm() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        clock.advance(30 * 60)
        service.refresh()
        #expect(service.ringingAlarms.map(\.id) == [alarm.id])
        #expect(rings.cancelled.contains(alarm.id))
        #expect(wakeCount == 1)
    }

    @Test func stoppingARepeatingAlarmSetsTheNextDay() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30, weekdays: Set(Locale.Weekday.ordered)))
        clock.advance(30 * 60)
        service.refresh()
        service.stop(alarm.id)
        #expect(service.ringing.isEmpty)
        #expect(service.upcoming[alarm.id] == at(16, 8, 30))
        #expect(rings.scheduled[alarm.id] == at(16, 8, 30))
        #expect(service.alarms[0].isEnabled)
    }

    @Test func stoppingAOneTimeAlarmTurnsItOff() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        clock.advance(30 * 60)
        service.refresh()
        service.stop(alarm.id)
        #expect(service.alarms[0].isEnabled == false)
        #expect(service.upcoming[alarm.id] == nil)
    }

    @Test func snoozeRingsAgainInNineMinutes() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        clock.advance(30 * 60)
        service.refresh()
        service.snooze(alarm.id)
        let end = clock.now.addingTimeInterval(9 * 60)
        #expect(service.ringing.isEmpty)
        #expect(service.upcoming[alarm.id] == end)
        #expect(service.isSnoozed(alarm.id))
        #expect(rings.scheduled[alarm.id] == end)
        clock.advance(9 * 60)
        service.refresh()
        #expect(service.ringingAlarms.map(\.id) == [alarm.id])
        #expect(!service.isSnoozed(alarm.id))
    }

    @Test func anAlarmWithoutSnoozeStopsInstead() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30, allowsSnooze: false))
        clock.advance(30 * 60)
        service.refresh()
        service.snooze(alarm.id)
        #expect(service.ringing.isEmpty)
        #expect(service.alarms[0].isEnabled == false)
    }

    @Test func nobodyAnsweringStopsItAfterTenMinutes() {
        let service = makeService()
        service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30, weekdays: Set(Locale.Weekday.ordered)))
        clock.advance(30 * 60)
        service.refresh()
        clock.advance(10 * 60)
        service.refresh()
        #expect(service.ringing.isEmpty)
    }

    @Test func turningAnAlarmOffSilencesItAndClearsItsRing() {
        let service = makeService()
        let alarm = service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        clock.advance(30 * 60)
        service.refresh()
        service.setEnabled(alarm.id, false)
        #expect(service.ringing.isEmpty)
        #expect(service.upcoming[alarm.id] == nil)
        service.setEnabled(alarm.id, true)
        #expect(service.upcoming[alarm.id] == at(16, 8, 30))
    }

    // MARK: Relaunch

    @Test func anAlarmDueWhileClosedRingsOnLaunchIfRecent() {
        let alarm = makeService().add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        clock.advance(35 * 60)
        let relaunched = makeService()
        #expect(relaunched.ringingAlarms.map(\.id) == [alarm.id])
    }

    @Test func aMissedAlarmDoesNotRingLate() {
        makeService().add(HomeAlarm(ownerID: owner, hour: 8, minute: 30, weekdays: Set(Locale.Weekday.ordered)))
        clock.advance(2 * 60 * 60)
        let relaunched = makeService()
        #expect(relaunched.ringing.isEmpty)
        #expect(relaunched.upcoming.values.first == at(16, 8, 30))
    }

    @Test func anAlarmStoppedOnTheLockScreenDoesNotRingAgain() {
        let alarm = makeService().add(HomeAlarm(ownerID: owner, hour: 8, minute: 30))
        rings.dismissedOutside = [alarm.id]
        clock.advance(31 * 60)
        let relaunched = makeService()
        #expect(relaunched.ringing.isEmpty)
        #expect(relaunched.alarms[0].isEnabled == false)
    }

    @Test func alarmsOfSomeoneWhoLeftAreRemoved() {
        let service = makeService()
        service.add(HomeAlarm(ownerID: owner, hour: 7, minute: 0))
        let other = service.add(HomeAlarm(ownerID: UUID(), hour: 6, minute: 0))
        service.removeAlarms(keepingOwners: [owner])
        #expect(service.alarms.map(\.ownerID) == [owner])
        #expect(rings.cancelled.contains(other.id))
        service.removeAlarms(keepingOwners: [])
        #expect(service.alarms.count == 1)
    }

    @Test func refreshRemovesAlarmsOfSomeoneWhoLeft() {
        let members = MemberList(ids: [owner])
        let clock = clock
        let service = AlarmService(store: store, events: events, rings: rings, clock: { clock.now },
                                   calendar: Self.utc, owners: { members.ids })
        service.add(HomeAlarm(ownerID: owner, hour: 7, minute: 0))
        members.ids = [UUID()]
        service.refresh()
        #expect(service.alarms.isEmpty)
    }

    // MARK: Text

    @Test func repeatTextNamesCommonDays() {
        #expect(AlarmFormat.repeatText([]) == "Once")
        #expect(AlarmFormat.repeatText(Set(Locale.Weekday.ordered)) == "Every day")
        #expect(AlarmFormat.repeatText(Locale.Weekday.workweek) == "Weekdays")
        #expect(AlarmFormat.repeatText(Locale.Weekday.weekend) == "Weekends")
        #expect(AlarmFormat.countdown(to: clock.now.addingTimeInterval(9 * 3600 + 14 * 60), from: clock.now) == "in 9 hr 14 min")
        #expect(AlarmFormat.countdown(to: clock.now.addingTimeInterval(50 * 3600), from: clock.now) == "in 2 days 2 hr")
    }
}
