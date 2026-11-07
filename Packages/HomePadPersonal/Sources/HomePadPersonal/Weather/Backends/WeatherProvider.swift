import Foundation

/// One source of forecasts. The weather service tries providers in order and
/// uses the first that succeeds, so WeatherKit problems fall back to Open-Meteo.
protocol WeatherProvider: Sendable {
    var source: WeatherSource { get }
    /// Fetches current, hourly and daily weather for a place.
    func forecast(for place: WeatherPlace) async throws -> WeatherForecast
}

enum WeatherProviderError: LocalizedError {
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let reason): "The weather service answered with an error: \(reason)"
        }
    }
}
