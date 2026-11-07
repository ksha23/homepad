import Foundation

/// Free forecasts from open-meteo.com. No account or key is needed for
/// non-commercial use, and the data is CC BY 4.0, so the Weather app credits it.
struct OpenMeteoProvider: WeatherProvider {
    let source = WeatherSource.openMeteo
    var session: URLSession = .shared

    func forecast(for place: WeatherPlace) async throws -> WeatherForecast {
        let (data, response) = try await session.data(from: Self.url(for: place))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return try Self.decode(data, status: status, placeName: place.name)
    }

    /// Decodes a response body. Separate from networking so tests can feed fixtures.
    static func decode(_ data: Data, status: Int = 200, placeName: String, fetchedAt: Date = Date()) throws -> WeatherForecast {
        let decoder = JSONDecoder()
        if status >= 400 || (try? decoder.decode(OpenMeteoResponse.ErrorBody.self, from: data))?.error == true {
            let reason = (try? decoder.decode(OpenMeteoResponse.ErrorBody.self, from: data))?.reason ?? "HTTP \(status)"
            throw WeatherProviderError.badResponse(reason)
        }
        return try decoder.decode(OpenMeteoResponse.self, from: data).forecast(placeName: placeName, fetchedAt: fetchedAt)
    }

    static func url(for place: WeatherPlace) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max,wind_speed_10m_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "forecast_hours", value: "48"),
        ]
        return components.url!
    }
}
