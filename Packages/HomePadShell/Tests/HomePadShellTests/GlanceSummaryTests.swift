import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadShell

/// What the glance says, from plain values, and how the header fits it.
@MainActor
@Suite struct GlanceSummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    /// 2:00 PM on a weekday.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 14))!
    }

    private func at(_ hour: Double, dayOffset: Int = 0) -> Date {
        calendar.startOfDay(for: now).addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3600)
    }

    private func event(_ title: String, _ start: Double, _ end: Double, allDay: Bool = false) -> CalendarItem {
        CalendarItem(id: title, title: title, start: at(start), end: at(end), isAllDay: allDay)
    }

    private func reminder(_ title: String, due: Date?, timed: Bool = false) -> CalendarItem {
        let date = due ?? .distantFuture
        return CalendarItem(id: title, title: title, start: date, end: date, isAllDay: !timed, isReminder: true)
    }

    private func accessory(_ name: String, _ kind: AccessoryKind, room: String? = nil, deviceClass: String? = nil,
                           state: AccessoryState) -> HomeAccessory {
        HomeAccessory(id: name, name: name, room: room, kind: kind, backend: .demo, state: state, deviceClass: deviceClass)
    }

    private func summary(_ personal: GlanceSummary.Personal? = nil, accessories: [HomeAccessory] = [],
                         timers: [HomeTimer] = []) -> GlanceSummary {
        GlanceSummary.make(personal: personal, accessories: accessories, timers: timers, weather: nil, now: now, calendar: calendar)
    }

    // MARK: Calendar and reminders

    @Test func eventsLeftTodayCountAllDayAndUnfinishedOnes() {
        let events = [event("Breakfast", 8, 9), event("Standup", 13.5, 14.5), event("Dentist", 15, 16),
                      event("Birthday", 0, 24, allDay: true)]
        let result = summary(GlanceSummary.Personal(events: events))
        #expect(result.events?.count == 3)
        // The one on now comes before the next one.
        #expect(result.events?.next.title == "Standup")
        let item = result.items(includingTimers: false, now: now).first
        #expect(item?.phrase == "3 events")
        #expect(item?.detail == "Now: Standup")
    }

    @Test func theNextEventLeadsWithItsTime() {
        let result = summary(GlanceSummary.Personal(events: [event("Dentist", 15, 16)]))
        let detail = result.items(includingTimers: false, now: now).first?.detail ?? ""
        #expect(result.items(includingTimers: false, now: now).first?.phrase == "1 event")
        #expect(detail.hasSuffix(" Dentist"))
        #expect(detail.hasPrefix(at(15).formatted(date: .omitted, time: .shortened)))
    }

    @Test func aDayWithNothingLeftHasNoEvents() {
        let result = summary(GlanceSummary.Personal(events: [event("Breakfast", 8, 9)]))
        #expect(result.events == nil)
    }

    @Test func remindersDueTodayAndOverdueCountUndatedAndLaterOnesDoNot() {
        let reminders = [
            reminder("Call plumber", due: at(0, dayOffset: -1)),     // yesterday, overdue
            reminder("Send slides", due: at(11), timed: true),        // this morning, overdue
            reminder("Pick up dry cleaning", due: at(17), timed: true), // later today
            reminder("Water plants", due: at(0)),                     // today, no time
            reminder("Renew passport", due: at(0, dayOffset: 3)),     // later
            reminder("Milk", due: nil),                               // undated
        ]
        let result = summary(GlanceSummary.Personal(reminders: reminders))
        #expect(result.reminders?.count == 4)
        #expect(result.reminders?.overdue == 2)
        let item = result.items(includingTimers: false).first
        #expect(item?.phrase == "4 reminders")
        #expect(item?.detail == "2 overdue")
    }

    @Test func withNothingOverdueTheFirstReminderIsTheDetail() {
        let result = summary(GlanceSummary.Personal(reminders: [reminder("Pick up dry cleaning", due: at(17), timed: true)]))
        #expect(result.items(includingTimers: false).first?.detail == "Pick up dry cleaning")
    }

    @Test func personalPartsStayOutWhileNobodyIsRecognized() {
        let light = accessory("Lamp", .light, state: AccessoryState(isOn: true))
        let locked = summary(nil, accessories: [light])
        #expect(locked.events == nil && locked.reminders == nil && locked.unreadMessages == 0)
        #expect(locked.items(includingTimers: false).map(\.id) == [.home(.lights)])
    }

    // MARK: Home

    @Test func whatIsOnIsCountedByKindEachDeviceOnce() {
        var lamp = accessory("Floor Lamp", .light, room: "Living Room", state: AccessoryState(isOn: true))
        lamp.groupID = "group"
        let accessories = [
            lamp,
            accessory("Sofa Lamps", .light, room: "Living Room", state: AccessoryState(isOn: true)).withMembers(["Floor Lamp"]),
            accessory("Bedroom Lights", .light, room: "Bedroom", state: AccessoryState(isOn: true)),
            accessory("Ceiling Light", .light, room: "Bedroom", state: AccessoryState(isOn: true)),
            accessory("Desk Lamp", .light, room: "Office", state: AccessoryState(isOn: false)),
            accessory("Porch Light", .light, room: "Outside", state: AccessoryState(isOn: true, isReachable: false)),
            accessory("Ceiling Fan", .fan, state: AccessoryState(isOn: true)),
            accessory("TV", .mediaPlayer, state: AccessoryState(isOn: true, isPlaying: false)),
            accessory("Speaker", .mediaPlayer, state: AccessoryState(isOn: true, isPlaying: true)),
            accessory("Thermostat", .thermostat, state: AccessoryState(hvacMode: .heat)),
            accessory("Hall Thermostat", .thermostat, state: AccessoryState(hvacMode: .off)),
        ]
        let result = summary(accessories: accessories)
        #expect(result.home.map(\.kind) == [.lights, .fans, .media, .climate])
        let lights = result.home.first
        #expect(lights?.count == 3)
        // The room with the most lights on comes first.
        #expect(lights?.rooms == ["Bedroom", "Living Room"])
        #expect(result.items(includingTimers: false).first?.phrase == "3 lights on")
        #expect(result.items(includingTimers: false).first?.detail == "Bedroom, Living Room")
        #expect(result.homeItems(namingAccessories: true).first?.detail == "Floor Lamp, Bedroom Lights, Ceiling Light")
    }

    @Test func whatNeedsALookIsPointedOut() {
        let accessories = [
            accessory("Front Door", .lock, state: AccessoryState(lockState: .unlocked)),
            accessory("Back Door", .lock, state: AccessoryState(lockState: .locked)),
            accessory("Garage", .garageDoor, state: AccessoryState(position: 1, doorState: .open)),
            // Home Assistant reports a door state, HomeKit's contact sensors only that they are active.
            accessory("Patio Door", .sensor, deviceClass: "door", state: AccessoryState(doorState: .open, isActive: true)),
            accessory("Side Door", .sensor, deviceClass: "opening", state: AccessoryState(isActive: true)),
            accessory("Shed Door", .sensor, deviceClass: "door", state: AccessoryState(doorState: .closed, isActive: false)),
            accessory("Kitchen Window", .sensor, deviceClass: "window", state: AccessoryState(doorState: .open)),
            accessory("Sink", .sensor, deviceClass: "moisture", state: AccessoryState(isActive: true)),
            accessory("Hallway Motion", .sensor, deviceClass: "motion", state: AccessoryState(isActive: true)),
        ]
        let result = summary(accessories: accessories)
        #expect(result.attention.map(\.kind) == [.leak, .unlocked, .garageOpen, .doorOpen, .windowOpen])
        let doors = result.attention.first { $0.kind == .doorOpen }
        #expect(doors?.names == ["Patio Door", "Side Door"])
        let items = result.items(includingTimers: false)
        #expect(items.first { $0.id == .attention(.doorOpen) }?.phrase == "2 doors open")
        #expect(items.first { $0.id == .attention(.unlocked) }?.phrase == "1 unlocked")
        #expect(items.first { $0.id == .attention(.unlocked) }?.detail == "Front Door")
        #expect(items.allSatisfy { $0.appID == GlanceAppID.home })
    }

    // MARK: Order and timers

    @Test func theDayComesFirstThenWhatNeedsALookThenWhatIsOn() {
        let personal = GlanceSummary.Personal(events: [event("Dentist", 15, 16)],
                                              reminders: [reminder("Water plants", due: at(0))], unreadMessages: 2)
        let accessories = [accessory("Lamp", .light, state: AccessoryState(isOn: true)),
                           accessory("Front Door", .lock, state: AccessoryState(lockState: .unlocked))]
        let timer = HomeTimer(label: "Pasta", duration: 600, status: .running, endDate: now.addingTimeInterval(300))
        let result = summary(personal, accessories: accessories, timers: [timer])
        // The header leaves timers to the timer pill beside it.
        #expect(result.items(includingTimers: false).map(\.id) == [.events, .reminders, .messages, .attention(.unlocked), .home(.lights)])
        #expect(result.items(includingTimers: true).last?.id == .timers)
        #expect(result.items(includingTimers: true).map(\.appID) == ["calendar", "reminders", "messages", "home", "home", "timers"])
        #expect(result.items(includingTimers: false)[2].phrase == "2 unread")
    }

    @Test func nothingAtAllIsEmpty() {
        let off = accessory("Lamp", .light, state: AccessoryState(isOn: false))
        #expect(summary(GlanceSummary.Personal(), accessories: [off]).isEmpty)
    }

    @Test func itChangesNextWhenAnEventEndsOrAReminderFallsDue() {
        let personal = GlanceSummary.Personal(events: [event("Dentist", 15, 16), event("Birthday", 0, 24, allDay: true)],
                                              reminders: [reminder("Dry cleaning", due: at(14.5), timed: true)])
        #expect(GlanceSummary.nextChange(personal: personal, now: now, calendar: calendar) == at(14.5))
        // With nothing timed left, at midnight.
        #expect(GlanceSummary.nextChange(personal: GlanceSummary.Personal(), now: now, calendar: calendar) == at(0, dayOffset: 1))
    }

    // MARK: The header

    @Test func theHeaderShrinksThingsFromTheEndBeforeDroppingAny() {
        let personal = GlanceSummary.Personal(events: [event("Dentist", 15, 16)], unreadMessages: 1)
        let items = summary(personal, accessories: [accessory("Lamp", .light, state: AccessoryState(isOn: true))])
            .items(includingTimers: false)
        let variants = MiniGlanceContent.variants(items: items, size: .large)
        // The first things keep the chosen size longest, the rest shrink to a symbol and a count.
        #expect(variants.map(\.size) == [.large, .large, .large, .small, .small, .small])
        #expect(variants.map(\.fullCount) == [3, 2, 1, 3, 2, 1])
        #expect(variants.map(\.items.count) == [3, 3, 3, 3, 2, 1])
        // Things are dropped from the end, so the day stays.
        #expect(variants.last?.items.map(\.id) == [.events])
        #expect(MiniGlanceContent.variants(items: items, size: .small).map(\.items.count) == [3, 2, 1])
        // With nothing to say, the quiet check at the chosen size, then small.
        #expect(MiniGlanceContent.variants(items: [], size: .medium).map(\.size) == [.medium, .small])
    }

    // MARK: The header's mini widget

    private let glanceSmall = MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: .small)

    private func decoded(_ json: String) throws -> HomeScreenLayout {
        try JSONDecoder().decode(HomeScreenLayout.self, from: Data(json.utf8))
    }

    @Test func theHeaderShowsTheSmallGlanceUntilChangedAndSavesTheChange() throws {
        var layout = HomeScreenLayout(pages: [[.app("a")]], knownAppIDs: ["a"])
        #expect(layout.miniWidget == glanceSmall)
        // A layout saved before the glance existed shows the default.
        #expect(try decoded(#"{"pages":[[]],"knownAppIDs":[]}"#).miniWidget == glanceSmall)
        // A size saved comes back.
        let large = MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: .large)
        layout.setMiniWidget(large)
        #expect(try JSONDecoder().decode(HomeScreenLayout.self, from: JSONEncoder().encode(layout)).miniWidget == large)
        // Removed stays removed, rather than coming back as the default.
        layout.setMiniWidget(nil)
        let removed = try JSONDecoder().decode(HomeScreenLayout.self, from: JSONEncoder().encode(layout))
        #expect(removed.miniWidget == nil)
        #expect(removed.pages == layout.pages)
        #expect(removed.knownAppIDs == layout.knownAppIDs)
    }

    @Test func aGlanceSavedBeforeMiniWidgetsKeepsItsSizeOrStaysRemoved() throws {
        let medium = try decoded(#"{"pages":[[]],"knownAppIDs":[],"glance":{"isShown":true,"size":"medium"}}"#)
        #expect(medium.miniWidget == MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: .medium))
        let large = try decoded(#"{"pages":[[]],"knownAppIDs":[],"glance":{"isShown":true,"size":"large"}}"#)
        #expect(large.miniWidget == MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: .large))
        let hidden = try decoded(#"{"pages":[[]],"knownAppIDs":[],"glance":{"isShown":false,"size":"large"}}"#)
        #expect(hidden.miniWidget == nil)
        // Saved again, it is a mini widget and the old key is gone.
        let resaved = try #require(String(data: JSONEncoder().encode(medium), encoding: .utf8))
        #expect(!resaved.contains("\"glance\""))
        #expect(try decoded(resaved).miniWidget == medium.miniWidget)
    }

    @Test func theSizeButtonStepsThroughTheSizes() {
        let glance = MiniWidgetDescriptor(id: GlanceMiniWidget.id, title: "Glance", systemImage: "square.text.square") { _ in
            EmptyView()
        }
        #expect(glance.size(after: .small) == .medium)
        #expect(glance.size(after: .medium) == .large)
        #expect(glance.size(after: .large) == .small)
        // A widget with fewer sizes steps through those and shows its first for one it lacks.
        let two = MiniWidgetDescriptor(id: "two", title: "Two", systemImage: "2.circle", supportedSizes: [.small, .large]) { _ in
            EmptyView()
        }
        #expect(two.size(after: .small) == .large)
        #expect(two.size(after: .large) == .small)
        #expect(two.shownSize(.medium) == .small)
    }
}

private extension HomeAccessory {
    func withMembers(_ ids: [String]) -> HomeAccessory {
        var copy = self
        copy.memberIDs = ids
        return copy
    }
}
