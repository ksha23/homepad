import Foundation

/// Keeps the last forecast on disk so weather shows instantly after a relaunch,
/// before the first refresh finishes.
struct ForecastCache {
    var url: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("homepad-weather-forecast.json")

    func load() -> WeatherForecast? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeatherForecast.self, from: data)
    }

    func save(_ forecast: WeatherForecast) {
        guard let data = try? JSONEncoder().encode(forecast) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
