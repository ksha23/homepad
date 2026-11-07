import Foundation

/// The subset of Open-Meteo's `/v1/forecast` response HomePad requests,
/// fetched with `timeformat=unixtime` so every time is an absolute instant.
/// Arrays may hold nulls at the end of the forecast range.
struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let time: TimeInterval
        let temperature_2m: Double
        let relative_humidity_2m: Double?
        let apparent_temperature: Double?
        let is_day: Int?
        let precipitation: Double?
        let weather_code: Int?
        let cloud_cover: Double?
        let pressure_msl: Double?
        let wind_speed_10m: Double?
        let wind_direction_10m: Double?
        let wind_gusts_10m: Double?
        let uv_index: Double?
    }

    struct Hourly: Decodable {
        let time: [TimeInterval]
        let temperature_2m: [Double?]
        let precipitation_probability: [Double?]?
        let weather_code: [Int?]
        let is_day: [Int?]?
        let wind_speed_10m: [Double?]?
    }

    struct Daily: Decodable {
        let time: [TimeInterval]
        let weather_code: [Int?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_probability_max: [Double?]?
        let precipitation_sum: [Double?]?
        let sunrise: [TimeInterval?]?
        let sunset: [TimeInterval?]?
        let uv_index_max: [Double?]?
        let wind_speed_10m_max: [Double?]?
    }

    let latitude: Double
    let longitude: Double
    let timezone: String?
    let utc_offset_seconds: Int?
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    /// Open-Meteo's error body: `{"error": true, "reason": "..."}`.
    struct ErrorBody: Decodable {
        let error: Bool
        let reason: String
    }
}

extension OpenMeteoResponse {
    /// Converts to HomePad's forecast model. Hours and days with a missing
    /// temperature are dropped rather than shown as zero.
    func forecast(placeName: String, fetchedAt: Date = Date()) -> WeatherForecast {
        let place = WeatherPlace(name: placeName, latitude: latitude, longitude: longitude, timeZoneID: timezone)
        let currentCondition = WeatherConditionKind(wmoCode: current.weather_code ?? 3)
        let conditions = CurrentConditions(
            date: Date(timeIntervalSince1970: current.time),
            temperature: current.temperature_2m,
            apparentTemperature: current.apparent_temperature,
            condition: currentCondition,
            isDaylight: (current.is_day ?? 1) == 1,
            humidity: current.relative_humidity_2m.map { $0 / 100 },
            windSpeed: current.wind_speed_10m,
            windDirection: current.wind_direction_10m,
            windGust: current.wind_gusts_10m,
            uvIndex: current.uv_index,
            pressure: current.pressure_msl,
            cloudCover: current.cloud_cover.map { $0 / 100 },
            precipitation: current.precipitation
        )
        return WeatherForecast(place: place, current: conditions, hourly: hours(), daily: days(), source: .openMeteo, fetchedAt: fetchedAt)
    }

    private func hours() -> [HourlyForecast] {
        guard let hourly else { return [] }
        return hourly.time.indices.compactMap { i in
            guard let temperature = hourly.temperature_2m[safe: i] ?? nil else { return nil }
            return HourlyForecast(
                date: Date(timeIntervalSince1970: hourly.time[i]),
                temperature: temperature,
                condition: WeatherConditionKind(wmoCode: (hourly.weather_code[safe: i] ?? nil) ?? 3),
                isDaylight: ((hourly.is_day?[safe: i] ?? nil) ?? 1) == 1,
                precipitationChance: (hourly.precipitation_probability?[safe: i] ?? nil).map { $0 / 100 },
                windSpeed: hourly.wind_speed_10m?[safe: i] ?? nil
            )
        }
    }

    private func days() -> [DailyForecast] {
        guard let daily else { return [] }
        return daily.time.indices.compactMap { i in
            guard let high = daily.temperature_2m_max[safe: i] ?? nil,
                  let low = daily.temperature_2m_min[safe: i] ?? nil else { return nil }
            return DailyForecast(
                date: Date(timeIntervalSince1970: daily.time[i]),
                high: high,
                low: low,
                condition: WeatherConditionKind(wmoCode: (daily.weather_code[safe: i] ?? nil) ?? 3),
                precipitationChance: (daily.precipitation_probability_max?[safe: i] ?? nil).map { $0 / 100 },
                precipitationAmount: daily.precipitation_sum?[safe: i] ?? nil,
                sunrise: (daily.sunrise?[safe: i] ?? nil).map(Date.init(timeIntervalSince1970:)),
                sunset: (daily.sunset?[safe: i] ?? nil).map(Date.init(timeIntervalSince1970:)),
                uvIndexMax: daily.uv_index_max?[safe: i] ?? nil,
                windSpeedMax: daily.wind_speed_10m_max?[safe: i] ?? nil
            )
        }
    }
}

extension Array {
    /// Nil instead of a crash when the API returns arrays of different lengths.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
