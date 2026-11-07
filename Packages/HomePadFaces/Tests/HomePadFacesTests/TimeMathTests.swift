import Foundation
import HomePadCore
import HomePadUI
import Testing
@testable import HomePadFaces

@Suite struct TimeMathTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(month: Int = 10, day: Int = 20, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func handAnglesAt1009() {
        let angles = ClockMath.angles(for: date(hour: 10, minute: 9, second: 30), calendar: calendar)
        #expect(abs(angles.hour - (10 + 9.5 / 60) * 30) < 0.001)
        #expect(abs(angles.minute - 9.5 * 6) < 0.001)
        #expect(angles.second == 180)
    }

    @Test func afternoonHoursWrapOnTheDial() {
        let angles = ClockMath.angles(for: date(hour: 15), calendar: calendar)
        #expect(angles.hour == 90)
    }

    @Test func hourDistanceIsCircular() {
        #expect(ClockMath.hourDistance(12, to: 0.5) == 0.5)
        #expect(ClockMath.hourDistance(1, to: 11) == 2)
        #expect(ClockMath.hourDistance(6, to: 0) == 6)
    }

    @Test func clockTextIn12And24Hours() {
        let morning = ClockText.parts(for: date(hour: 9, minute: 5), uses24Hour: false, calendar: calendar)
        #expect(morning == ClockText.Parts(hours: "9", minutes: "05", period: "AM"))
        let midnight = ClockText.parts(for: date(hour: 0, minute: 30), uses24Hour: false, calendar: calendar)
        #expect(midnight.joined == "12:30")
        #expect(midnight.period == "AM")
        let evening = ClockText.parts(for: date(hour: 21, minute: 41), uses24Hour: true, calendar: calendar)
        #expect(evening == ClockText.Parts(hours: "21", minutes: "41", period: nil))
    }

    @Test func localesPickTheirClock() {
        #expect(!ClockText.localeUses24Hour(Locale(identifier: "en_US")))
        #expect(ClockText.localeUses24Hour(Locale(identifier: "de_DE")))
    }

    @Test func fadeLightsNumeralsNearTheHour() {
        let noon = FadeCurve.daylight(hour: 12.5)
        #expect(noon > 0.99)
        #expect(FadeCurve.daylight(hour: 3) == 0)
        let near = FadeCurve.opacity(numeral: 10, hourPosition: 10.2, daylight: 1)
        let far = FadeCurve.opacity(numeral: 4, hourPosition: 10.2, daylight: 1)
        #expect(near == 1)
        #expect(far < 0.1)
        #expect(FadeCurve.opacity(numeral: 10, hourPosition: 10, daylight: 0) < near)
    }

    @Test func fadeLightSweepsAcrossTheDay() {
        #expect(abs(FadeCurve.lightAngle(hour: 6) - .pi) < 0.001)
        #expect(abs(FadeCurve.lightAngle(hour: 12.5) - .pi / 2) < 0.001)
        #expect(abs(FadeCurve.lightAngle(hour: 19)) < 0.001)
        #expect(FadeCurve.lightAngle(hour: 23) == .pi / 2)
    }

    @Test func worldCityOffsetsReadNaturally() {
        let noon = date(hour: 12)
        let chicago = TimeZone(identifier: "America/Chicago")!
        let tokyo = WorldCity.city("tokyo")!
        #expect(tokyo.hoursAhead(of: chicago, at: noon) == 14)
        #expect(tokyo.relativeLabel(from: chicago, at: date(hour: 12)) == "Tomorrow, +14 hrs")
        #expect(WorldCity.city("madison")!.relativeLabel(from: chicago, at: noon) == "Today, same time")
        #expect(WorldCity.city("mumbai")!.relativeLabel(from: chicago, at: noon).contains("10.5"))
        #expect(WorldCity.all.allSatisfy { TimeZone(identifier: $0.timeZoneID) != nil })
    }

    @Test func skyConditionsFromSymbols() {
        #expect(SkyCondition.from(symbolName: "cloud.sun.fill") == .partlyCloudy)
        #expect(SkyCondition.from(symbolName: "cloud.rain.fill") == .rain)
        #expect(SkyCondition.from(symbolName: "cloud.bolt.rain.fill") == .thunder)
        #expect(SkyCondition.from(symbolName: "snowflake") == .snow)
        #expect(SkyCondition.from(symbolName: "sun.max.fill") == .clear)
        #expect(SkyCondition.from(symbolName: "cloud.fill", conditionText: "Overcast") == .cloudy)
        #expect(SkyCondition.from(symbolName: "cloud.fog.fill") == .fog)
        #expect(SkyTime.at(hour: 6) == .dawn)
        #expect(SkyTime.at(hour: 13) == .day)
        #expect(SkyTime.at(hour: 18) == .dusk)
        #expect(SkyTime.at(hour: 22) == .night)
    }

    @Test func skyFollowsSunriseAndSunset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        func at(_ hour: Int, _ minute: Int, day: Int = 20) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        let sunrise = at(7, 12), sunset = at(18, 10)
        func sky(_ date: Date) -> SkyTime {
            SkyTime.at(date, sunrise: sunrise, sunset: sunset, isDaylight: nil, calendar: calendar)
        }
        // 5:55 AM is well before a 7:12 sunrise: night, not a daytime sky with a sun.
        #expect(sky(at(5, 55)) == .night)
        #expect(sky(at(6, 50)) == .dawn)
        #expect(sky(at(12, 0)) == .day)
        #expect(sky(at(18, 30)) == .dusk)
        #expect(sky(at(21, 0)) == .night)
        // Yesterday's sun times still apply after midnight.
        #expect(sky(at(12, 0, day: 21)) == .day)
        // Without sun times, the daylight flag or a moon symbol wins over the hour.
        #expect(SkyTime.at(at(6, 0), sunrise: nil, sunset: nil, isDaylight: false, calendar: calendar) == .night)
        #expect(SkyTime.at(at(6, 0), sunrise: nil, sunset: nil, isDaylight: nil, symbolName: "cloud.moon.fill", calendar: calendar) == .night)
        #expect(SkyTime.at(at(20, 0), sunrise: nil, sunset: nil, isDaylight: true, calendar: calendar) == .day)
    }

    @Test func sprigFollowsTheDay() {
        func look(_ hour: Int, sky: SkyCondition? = .partlyCloudy, month: Int = 10, day: Int = 20, timer: Bool = false) -> CritterLook {
            CritterBrain.look(.init(date: date(month: month, day: day, hour: hour), calendar: calendar, sky: sky,
                                    temperatureFahrenheit: 60, timerJustFinished: timer))
        }
        #expect(look(23) == CritterLook(pose: .sleeping, accessory: .nightcap))
        #expect(look(7).pose == .stretching)
        #expect(look(13).pose == .waving)
        #expect(look(20).pose == .reading)
        #expect(look(13, sky: .rain).pose == .umbrella)
        #expect(look(13, sky: .snow).accessory == .scarf)
        #expect(look(13, sky: .clear).accessory == .sunglasses)
        #expect(look(13, month: 10, day: 31).accessory == .pumpkinHat)
        #expect(look(23, month: 12, day: 25) == CritterLook(pose: .sleeping, accessory: .santaHat))
        #expect(look(13, timer: true).pose == .celebrating)
    }

    @Test func calendarsHidePersonalEventsUntilRecognized() {
        let start = date(hour: 9)
        let events = [
            CalendarItem(id: "a", title: "Dentist", start: start, end: start.addingTimeInterval(1800), calendarName: "Work"),
            CalendarItem(id: "b", title: "Soccer", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200), calendarName: "Family", isShared: true),
            CalendarItem(id: "c", title: "Holiday", start: start, end: start, isAllDay: true, calendarName: "family", isShared: true),
            CalendarItem(id: "d", title: "Buy milk", start: start, end: start, calendarName: "Family", isReminder: true, isShared: true),
        ]
        let guest = CalendarVisibility.visible(events, showPersonal: false)
        #expect(guest.map(\.id) == ["c", "b"])
        let member = CalendarVisibility.visible(events, showPersonal: true)
        #expect(member.map(\.id) == ["c", "a", "b"])
        #expect(CalendarVisibility.upcoming(member, after: start.addingTimeInterval(2000)).map(\.id) == ["b"])
    }

    @Test func configurationsFallBackToOptionDefaults() {
        var face = FaceConfiguration(faceID: "faces.numerals")
        #expect(face.color(NumeralsFace.color) == .green)
        face.values["color"] = "coral"
        #expect(face.color(NumeralsFace.color) == .coral)
        face.values["color"] = "porcelain"
        #expect(face.color(NumeralsFace.color) == .green)
        face.values["style"] = "heavy"
        #expect(face.value(NumeralsFace.style) == "heavy")
    }
}
