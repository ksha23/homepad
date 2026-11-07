import Foundation

/// Plain-text answers for the assistant tools. Pure, so tests can check wording.
enum ForecastSummary {
    /// One line per day: "Wednesday: Rain, high 54°, low 45°, 80% chance of precipitation."
    static func daily(_ forecast: WeatherForecast, days: Int, units: WeatherUnitSystem, locale: Locale = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.timeZone = forecast.timeZone
        let lines = forecast.daily.prefix(days).enumerated().map { index, day in
            let name = index == 0 ? "Today" : (index == 1 ? "Tomorrow" : day.date.formatted(style))
            var line = "\(name): \(day.condition.text), high \(units.temperatureText(day.high, locale: locale)), low \(units.temperatureText(day.low, locale: locale))"
            if let chance = day.precipitationChance, chance >= 0.1 {
                line += ", \(Int((chance * 100).rounded()))% chance of precipitation"
            }
            return line + "."
        }
        return "Forecast for \(forecast.place.name):\n" + lines.joined(separator: "\n")
    }

    /// "It is 9:59 AM on Tuesday in London, 6 hrs ahead of here."
    static func worldTime(city: WorldClockCity, at date: Date, home: TimeZone = .current, locale: Locale = .current) -> String {
        let zone = city.timeZone
        var dayStyle = Date.FormatStyle.dateTime.weekday(.wide)
        dayStyle.timeZone = zone
        let offset = TimeZoneMath.offset(of: zone, from: home, at: date)
        let relation: String
        if offset == 0 {
            relation = "the same time as here"
        } else {
            let text = TimeZoneMath.offsetText(seconds: abs(offset)).dropFirst()
            relation = "\(text) \(offset > 0 ? "ahead of" : "behind") here"
        }
        return "It is \(TimeZoneMath.timeText(at: date, in: zone, locale: locale)) on \(date.formatted(dayStyle)) in \(city.name), \(relation)."
    }
}
