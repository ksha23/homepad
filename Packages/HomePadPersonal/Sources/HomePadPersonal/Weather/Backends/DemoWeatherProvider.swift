import Foundation

/// A plausible autumn forecast for demo mode, built around the current time.
struct DemoWeatherProvider: WeatherProvider {
    let source = WeatherSource.demo

    func forecast(for place: WeatherPlace) async throws -> WeatherForecast {
        Self.forecast(for: place)
    }

    static func forecast(for place: WeatherPlace, now: Date = Date()) -> WeatherForecast {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let pattern: [WeatherConditionKind] = [.partlyCloudy, .partlyCloudy, .clear, .clear, .clear, .mostlyClear, .partlyCloudy, .cloudy]
        let hours = (0..<48).map { offset -> HourlyForecast in
            let date = hourStart.addingTimeInterval(Double(offset) * 3600)
            let hour = calendar.component(.hour, from: date)
            let daylight = (7..<19).contains(hour)
            let temperature = 9 + 5 * sin((Double(hour) - 9) / 24 * 2 * .pi)
            return HourlyForecast(date: date, temperature: temperature, condition: pattern[offset % pattern.count],
                                  isDaylight: daylight, precipitationChance: offset > 30 ? 0.4 : 0.05, windSpeed: 12)
        }
        let dayPattern: [(WeatherConditionKind, Double, Double, Double)] = [
            (.partlyCloudy, 14, 9, 0.1), (.clear, 16, 8, 0), (.rain, 12, 7, 0.8), (.cloudy, 11, 5, 0.3),
            (.mostlyClear, 13, 4, 0.05), (.snow, 3, -2, 0.6), (.clear, 9, 1, 0), (.partlyCloudy, 12, 6, 0.1),
            (.thunderstorm, 17, 11, 0.7), (.mostlyCloudy, 13, 8, 0.2),
        ]
        let today = calendar.startOfDay(for: now)
        let todayTemperatures = (0..<24).map { 9 + 5 * sin((Double($0) - 9) / 24 * 2 * .pi) }
        let days = dayPattern.enumerated().map { index, entry in
            let date = calendar.date(byAdding: .day, value: index, to: today) ?? today
            let high = index == 0 ? (todayTemperatures.max() ?? entry.1) : entry.1
            let low = index == 0 ? (todayTemperatures.min() ?? entry.2) : entry.2
            return DailyForecast(date: date, high: high, low: low, condition: entry.0, precipitationChance: entry.3,
                                 precipitationAmount: entry.3 * 6, sunrise: date.addingTimeInterval(7.2 * 3600),
                                 sunset: date.addingTimeInterval(18.1 * 3600), uvIndexMax: 3, windSpeedMax: 20)
        }
        let first = hours.first
        let temperature = first?.temperature ?? 10
        let isDaylight = first?.isDaylight ?? true
        let current = CurrentConditions(date: now, temperature: temperature, apparentTemperature: temperature - 1.4,
                                        condition: first?.condition ?? .partlyCloudy, isDaylight: isDaylight, humidity: 0.62,
                                        windSpeed: 13, windDirection: 250, windGust: 24, uvIndex: isDaylight ? 3 : 0,
                                        pressure: 1018, cloudCover: 0.4, precipitation: 0)
        return WeatherForecast(place: place, current: current, hourly: hours, daily: days, source: .demo, fetchedAt: now)
    }
}
