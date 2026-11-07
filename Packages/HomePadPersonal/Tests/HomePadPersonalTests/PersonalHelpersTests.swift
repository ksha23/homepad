import Foundation
import Testing
@testable import HomePadPersonal

@Suite struct PersonalHelpersTests {
    var sundayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func weekStartsOnTheLocalesFirstDay() throws {
        let tuesday = try Date("2026-10-20T15:00:00Z", strategy: .iso8601)
        let week = CalendarDateMath.week(containing: tuesday, calendar: sundayFirst)
        #expect(week.count == 7)
        #expect(sundayFirst.component(.weekday, from: week[0]) == 1)
        #expect(sundayFirst.component(.day, from: week[0]) == 18)
    }

    @Test func monthGridCoversWholeWeeks() throws {
        let october = try Date("2026-10-15T15:00:00Z", strategy: .iso8601)
        let grid = CalendarDateMath.monthGrid(containing: october, calendar: sundayFirst)
        // October 2026 starts on a Thursday and ends on a Saturday.
        #expect(grid.count == 35)
        #expect(sundayFirst.dateComponents([.month, .day], from: grid[0]) == DateComponents(month: 9, day: 27))
        #expect(sundayFirst.dateComponents([.month, .day], from: grid[34]) == DateComponents(month: 10, day: 31))
    }

    @Test func monthIntervalEndsAfterTheLastGridDay() throws {
        let october = try Date("2026-10-15T15:00:00Z", strategy: .iso8601)
        let interval = CalendarDateMath.interval(for: .month, around: october, calendar: sundayFirst)
        #expect(interval.duration > 34 * 86_400)
        #expect(CalendarDateMath.step(october, mode: .week, by: 1, calendar: sundayFirst) == october.addingTimeInterval(7 * 86_400))
    }

    @Test func reminderMatcherUnderstandsLooseWords() {
        func item(_ title: String, done: Bool = false) -> ReminderItem {
            ReminderItem(id: title, title: title, isCompleted: done, listID: "g", listTitle: "Groceries", colorHex: "#00FF00")
        }
        let items = [item("Oat milk"), item("Coffee beans"), item("Eggs", done: true), item("Bananas")]
        #expect(ReminderMatcher.bestMatch(for: "the milk", in: items)?.title == "Oat milk")
        #expect(ReminderMatcher.bestMatch(for: "COFFEE BEANS", in: items)?.title == "Coffee beans")
        #expect(ReminderMatcher.bestMatch(for: "eggs", in: items) == nil)
        #expect(ReminderMatcher.bestMatch(for: "bread", in: items) == nil)
    }

    @Test func dailyForecastSummary() {
        let place = WeatherPlace(name: "Madison", latitude: 43, longitude: -89, timeZoneID: "America/Chicago")
        let forecast = DemoWeatherProvider.forecast(for: place, now: Date(timeIntervalSince1970: 1_792_485_000))
        let text = ForecastSummary.daily(forecast, days: 3, units: .us, locale: Locale(identifier: "en_US"))
        let lines = text.split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == "Forecast for Madison:")
        #expect(lines[1].hasPrefix("Today: Partly Cloudy, high"))
        #expect(lines[2].hasPrefix("Tomorrow: Clear"))
        #expect(lines[3].contains("80% chance of precipitation"))
    }
}
