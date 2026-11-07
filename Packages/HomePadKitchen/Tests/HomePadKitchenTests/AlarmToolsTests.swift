import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// The assistant's alarm tools, called by name with JSON arguments, the way
/// the assistant calls them.
@MainActor
@Suite struct AlarmToolsTests {
    let clock = TestClock()
    let rings = RecordingRings()
    let household = Household(store: SettingsStore(defaults: UserDefaults(suiteName: "alarm-tools-\(UUID().uuidString)")!))
    let service: AlarmService
    let alex = HouseholdMember(name: "Alex", avatar: "🦊", colorHex: "#FF9500", isAdmin: true)
    let sam = HouseholdMember(name: "Sam", avatar: "🐻", colorHex: "#34C759", isAdmin: false)

    init() {
        let clock = clock
        let file = FileManager.default.temporaryDirectory.appending(path: "alarm-tools-\(UUID().uuidString)/alarms.json")
        service = AlarmService(store: AlarmStateStore(fileURL: file), events: nil, rings: rings,
                               clock: { clock.now }, calendar: AlarmServiceTests.utc)
        household.add(alex)
        household.add(sam)
    }

    private func call(_ name: String, _ arguments: [String: JSONValue] = [:]) async throws -> String {
        let clock = clock
        let tools = AlarmTools.make(service: service, household: household, clock: { clock.now })
        let tool = try #require(tools.first(where: { $0.name == name }))
        #expect(tool.requiresRecognizedMember)
        return try await tool.handler(.object(arguments))
    }

    @Test func setAnAlarmForSevenMakesTheRecognizedPersonsAlarm() async throws {
        household.recognize(alex.id, now: clock.now)
        let reply = try await call("set_alarm", ["hour": 7])
        let alarm = try #require(service.alarms.first)
        #expect(alarm.ownerID == alex.id)
        #expect(alarm.hour == 7 && alarm.minute == 0 && !alarm.repeats)
        #expect(reply.hasPrefix("Alarm set for"))
        #expect(reply.contains("tomorrow"))
    }

    @Test func setAlarmTwiceTurnsTheSameOneOn() async throws {
        household.recognize(alex.id, now: clock.now)
        _ = try await call("set_alarm", ["hour": 6, "minute": 30, "repeat": "weekdays", "label": "Gym"])
        service.setEnabled(service.alarms[0].id, false)
        _ = try await call("set_alarm", ["hour": 6, "minute": 30, "repeat": "weekdays"])
        #expect(service.alarms.count == 1)
        #expect(service.alarms[0].isEnabled)
        #expect(service.alarms[0].title == "Gym")
    }

    @Test func nobodyRecognizedGetsNoAlarm() async throws {
        let reply = try await call("set_alarm", ["hour": 7])
        #expect(service.alarms.isEmpty)
        #expect(reply.contains("personal"))
    }

    @Test func turnOffMyAlarmsLeavesOtherPeoplesOn() async throws {
        service.add(HomeAlarm(ownerID: alex.id, hour: 6, minute: 30))
        service.add(HomeAlarm(ownerID: alex.id, hour: 9, minute: 0))
        service.add(HomeAlarm(ownerID: sam.id, hour: 7, minute: 0))
        household.recognize(alex.id, now: clock.now)
        let reply = try await call("turn_off_alarms")
        #expect(reply == "Turned off 2 alarms.")
        let alexOn = service.alarms(ownedBy: alex.id).filter(\.isEnabled)
        let samOn = service.alarms(ownedBy: sam.id).filter(\.isEnabled)
        #expect(alexOn.isEmpty)
        #expect(samOn.count == 1)
    }

    @Test func turnOffWhileRingingStopsItAndKeepsItOn() async throws {
        let alarm = service.add(HomeAlarm(ownerID: alex.id, hour: 8, minute: 30, weekdays: Set(Locale.Weekday.ordered)))
        clock.advance(30 * 60)
        service.refresh()
        household.recognize(alex.id, now: clock.now)
        let reply = try await call("turn_off_alarms")
        #expect(reply.hasPrefix("Stopped your"))
        #expect(service.ringing.isEmpty)
        #expect(service.alarms[0].isEnabled)
        #expect(service.upcoming[alarm.id] != nil)
    }

    @Test func listAlarmsNamesEachOne() async throws {
        service.add(HomeAlarm(ownerID: alex.id, hour: 6, minute: 30, label: "Gym", weekdays: Locale.Weekday.workweek))
        service.add(HomeAlarm(ownerID: alex.id, hour: 21, minute: 45, label: "Pills", isEnabled: false))
        household.recognize(alex.id, now: clock.now)
        let reply = try await call("list_alarms")
        #expect(reply.contains("Gym, weekdays, on"))
        #expect(reply.contains("Pills, once, off"))
    }

    @Test func spokenDaysParse() {
        #expect(AlarmRepeatParser.weekdays(from: "once") == [])
        #expect(AlarmRepeatParser.weekdays(from: "Weekdays") == Locale.Weekday.workweek)
        #expect(AlarmRepeatParser.weekdays(from: "every day")?.count == 7)
        #expect(AlarmRepeatParser.weekdays(from: "monday, wednesday and friday") == [.monday, .wednesday, .friday])
        #expect(AlarmRepeatParser.weekdays(from: "Tues, Thurs") == [.tuesday, .thursday])
        #expect(AlarmRepeatParser.weekdays(from: "soon") == nil)
    }
}
