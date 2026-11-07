import Foundation
import Testing
@testable import HomePadPersonal

@Suite struct OpenMeteoDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func decodesFullForecast() throws {
        let forecast = try OpenMeteoProvider.decode(fixture("open-meteo-madison"), placeName: "Madison")
        #expect(forecast.source == .openMeteo)
        #expect(forecast.place.name == "Madison")
        #expect(forecast.place.timeZoneID == "America/Chicago")
        #expect(forecast.timeZone.identifier == "America/Chicago")

        let now = forecast.current
        #expect(now.date == Date(timeIntervalSince1970: 1_792_485_000))
        #expect(now.temperature == 4.8)
        #expect(now.apparentTemperature == 2.2)
        #expect(now.condition == .clear)
        #expect(now.isDaylight == false)
        #expect(now.humidity == 0.87)
        #expect(now.cloudCover == 0.1)
        #expect(now.windSpeed == 6.5)
        #expect(now.windDirection == 84)
        #expect(now.pressure == 1027.4)
    }

    @Test func decodesHourlyFromTheCurrentHour() throws {
        let forecast = try OpenMeteoProvider.decode(fixture("open-meteo-madison"), placeName: "Madison")
        #expect(forecast.hourly.count == 48)
        let first = try #require(forecast.hourly.first)
        #expect(first.date == Date(timeIntervalSince1970: 1_792_483_200))
        #expect(first.temperature == 5.2)
        #expect(first.precipitationChance == 0)
        #expect(first.isDaylight == false)
        #expect(forecast.hourly.last?.date == Date(timeIntervalSince1970: 1_792_652_400))
    }

    @Test func dailyDatesAreLocalMidnight() throws {
        let forecast = try OpenMeteoProvider.decode(fixture("open-meteo-madison"), placeName: "Madison")
        #expect(forecast.daily.count == 10)
        let today = try #require(forecast.today)
        #expect(today.date == Date(timeIntervalSince1970: 1_792_472_400))
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        #expect(chicago.dateComponents([.hour, .minute], from: today.date) == DateComponents(hour: 0, minute: 0))
        #expect(today.high == 18.2)
        #expect(today.low == 3.7)
        #expect(today.condition == .fog)
        #expect(today.sunrise == Date(timeIntervalSince1970: 1_792_498_644))
        #expect(today.uvIndexMax == 4)
        #expect(forecast.daily.last?.precipitationChance == 0.18)
    }

    @Test func toleratesNullsAndMissingFields() throws {
        let forecast = try OpenMeteoProvider.decode(fixture("open-meteo-sparse"), placeName: "Tokyo")
        #expect(forecast.current.condition == .rain)
        #expect(forecast.current.humidity == nil)
        #expect(forecast.current.windSpeed == nil)
        // The hour with a null temperature is dropped, a null code falls back to cloudy.
        #expect(forecast.hourly.map(\.temperature) == [18.0, 17.1, 16.5])
        #expect(forecast.hourly[1].condition == .cloudy)
        #expect(forecast.hourly.allSatisfy { $0.precipitationChance == nil })
        // The day with a null high is dropped.
        #expect(forecast.daily.count == 2)
        #expect(forecast.daily[1].condition == .thunderstorm)
        #expect(forecast.daily[1].sunrise == nil)
        #expect(forecast.daily[0].precipitationChance == 0.9)
    }

    @Test func errorBodyThrows() throws {
        #expect(throws: WeatherProviderError.self) {
            try OpenMeteoProvider.decode(fixture("open-meteo-error"), status: 400, placeName: "Nowhere")
        }
        #expect(throws: WeatherProviderError.self) {
            try OpenMeteoProvider.decode(fixture("open-meteo-error"), status: 200, placeName: "Nowhere")
        }
    }

    @Test func requestAsksForUnixTimeInTheLocationsZone() throws {
        let url = OpenMeteoProvider.url(for: WeatherPlace(name: "Madison", latitude: 43.0731, longitude: -89.4012))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["timeformat"] == "unixtime")
        #expect(query["timezone"] == "auto")
        #expect(query["latitude"] == "43.0731")
        #expect(query["forecast_days"] == "10")
    }

    @Test(arguments: [
        (0, WeatherConditionKind.clear), (2, .partlyCloudy), (3, .cloudy), (45, .fog), (53, .drizzle),
        (61, .rain), (65, .heavyRain), (67, .freezingRain), (73, .snow), (75, .heavySnow), (95, .thunderstorm), (99, .hail), (12345, .cloudy),
    ])
    func mapsWMOCodes(code: Int, expected: WeatherConditionKind) {
        #expect(WeatherConditionKind(wmoCode: code) == expected)
    }

    @Test func convertsUnits() {
        let us = Locale(identifier: "en_US")
        #expect(WeatherUnitSystem.us.temperatureText(0) == "32°")
        #expect(WeatherUnitSystem.metric.temperatureText(12.6) == "13°")
        #expect(WeatherUnitSystem.us.windText(16.09344) == "10 mph")
        #expect(WeatherUnitSystem.metric.windText(19.4) == "19 km/h")
        #expect(WeatherUnitSystem.automatic.usesUSUnits(locale: us))
        #expect(!WeatherUnitSystem.automatic.usesUSUnits(locale: Locale(identifier: "de_DE")))
    }
}
