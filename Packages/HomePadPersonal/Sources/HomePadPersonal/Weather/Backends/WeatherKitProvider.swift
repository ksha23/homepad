import CoreLocation
import Foundation
import WeatherKit

/// Apple Weather through WeatherKit. Needs the WeatherKit capability on the
/// App ID and a provisioning profile that includes it. When either is missing
/// (common for development builds and the simulator) every call throws and
/// the service falls back to Open-Meteo.
struct WeatherKitProvider: WeatherProvider {
    let source = WeatherSource.weatherKit

    func forecast(for place: WeatherPlace) async throws -> WeatherForecast {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let now = Date()
        let (current, hourly, daily) = try await WeatherKit.WeatherService.shared.weather(
            for: location,
            including: .current,
            .hourly(startDate: now, endDate: now.addingTimeInterval(48 * 3600)),
            .daily(startDate: Calendar.current.startOfDay(for: now), endDate: now.addingTimeInterval(10 * 86_400))
        )
        let conditions = CurrentConditions(
            date: current.date,
            temperature: current.temperature.converted(to: .celsius).value,
            apparentTemperature: current.apparentTemperature.converted(to: .celsius).value,
            condition: Self.kind(current.condition),
            isDaylight: current.isDaylight,
            humidity: current.humidity,
            windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
            windDirection: current.wind.direction.converted(to: .degrees).value,
            windGust: current.wind.gust?.converted(to: .kilometersPerHour).value,
            uvIndex: Double(current.uvIndex.value),
            pressure: current.pressure.converted(to: .hectopascals).value,
            cloudCover: current.cloudCover
        )
        let hours = hourly.forecast.map { hour in
            HourlyForecast(
                date: hour.date,
                temperature: hour.temperature.converted(to: .celsius).value,
                condition: Self.kind(hour.condition),
                isDaylight: hour.isDaylight,
                precipitationChance: hour.precipitationChance,
                windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
        let days = daily.forecast.map { day in
            DailyForecast(
                date: day.date,
                high: day.highTemperature.converted(to: .celsius).value,
                low: day.lowTemperature.converted(to: .celsius).value,
                condition: Self.kind(day.condition),
                precipitationChance: day.precipitationChance,
                precipitationAmount: day.precipitationAmountByType.precipitation.converted(to: .millimeters).value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset,
                uvIndexMax: Double(day.uvIndex.value),
                windSpeedMax: day.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
        return WeatherForecast(place: place, current: conditions, hourly: hours, daily: days, source: .weatherKit, fetchedAt: now)
    }

    /// Apple's legally required attribution (service name and legal page).
    static func attribution() async -> (name: String, legalURL: URL)? {
        guard let attribution = try? await WeatherKit.WeatherService.shared.attribution else { return nil }
        return (attribution.serviceName, attribution.legalPageURL)
    }

    static func kind(_ condition: WeatherCondition) -> WeatherConditionKind {
        switch condition {
        case .clear, .hot, .frigid: .clear
        case .mostlyClear: .mostlyClear
        case .partlyCloudy, .sunShowers, .sunFlurries: .partlyCloudy
        case .mostlyCloudy: .mostlyCloudy
        case .cloudy: .cloudy
        case .foggy: .fog
        case .haze, .smoky, .blowingDust: .haze
        case .breezy, .windy: .windy
        case .drizzle: .drizzle
        case .rain: .rain
        case .heavyRain, .tropicalStorm, .hurricane: .heavyRain
        case .freezingDrizzle, .freezingRain: .freezingRain
        case .sleet, .wintryMix: .sleet
        case .flurries: .flurries
        case .snow, .blowingSnow: .snow
        case .heavySnow, .blizzard: .heavySnow
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms: .thunderstorm
        case .hail: .hail
        @unknown default: .cloudy
        }
    }
}
