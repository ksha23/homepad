import Foundation
import Testing
@testable import HomePadPersonal

/// The 12.9-inch iPad showed a sun and 62° under "Now" at 7:05 PM: the forecast
/// was fetched in the 6 PM hour, which was still daylight.
@Suite struct UpcomingHoursTests {
    /// 2026-10-20 6:00 PM in Chicago.
    let sixPM = Date(timeIntervalSince1970: 1_792_537_200)

    func forecast() -> WeatherForecast {
        let hours: [HourlyForecast] = (0..<4).map { (offset: Int) -> HourlyForecast in
            let step = Double(offset)
            let condition: WeatherConditionKind = offset == 0 ? .clear : .partlyCloudy
            return HourlyForecast(date: sixPM.addingTimeInterval(step * 3600), temperature: 17 - step,
                                  condition: condition, isDaylight: offset == 0, precipitationChance: 0.1 * step, windSpeed: 10)
        }
        let current = CurrentConditions(date: sixPM.addingTimeInterval(50 * 60), temperature: 15, condition: .clear,
                                        isDaylight: false, windSpeed: 6)
        return WeatherForecast(place: WeatherPlace(name: "Madison", latitude: 43.07, longitude: -89.4),
                               current: current, hourly: hours, daily: [], source: .weatherKit, fetchedAt: current.date)
    }

    @Test func finishedHoursLeaveAndNowShowsTheCurrentConditions() {
        let hours = forecast().upcomingHours(at: sixPM.addingTimeInterval(65 * 60))
        #expect(hours.map(\.date) == [sixPM.addingTimeInterval(3600), sixPM.addingTimeInterval(7200), sixPM.addingTimeInterval(10800)])
        #expect(hours[0].temperature == 15)
        #expect(hours[0].condition == .clear)
        #expect(hours[0].isDaylight == false)
        #expect(hours[0].windSpeed == 6)
        // The hour's own chance of rain stays: current conditions have none.
        #expect(hours[0].precipitationChance == 0.1)
        #expect(hours[1].temperature == 15 && hours[1].condition == .partlyCloudy)
    }

    @Test func theCurrentHourAlsoShowsTheCurrentConditions() {
        let hours = forecast().upcomingHours(at: sixPM.addingTimeInterval(55 * 60))
        #expect(hours.count == 4)
        #expect(hours[0].date == sixPM)
        #expect(hours[0].temperature == 15 && hours[0].isDaylight == false)
    }

    @Test func aForecastFromBeforeItsHoursIsLeftAlone() {
        let hours = forecast().upcomingHours(at: sixPM.addingTimeInterval(-10 * 60))
        #expect(hours == forecast().hourly)
    }

    @Test func aForecastThatRanOutIsEmpty() {
        #expect(forecast().upcomingHours(at: sixPM.addingTimeInterval(5 * 3600)).isEmpty)
    }
}
