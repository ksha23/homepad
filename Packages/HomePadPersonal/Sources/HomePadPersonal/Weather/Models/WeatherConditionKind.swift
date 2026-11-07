import Foundation

/// Backend-neutral weather condition. WeatherKit conditions and WMO codes
/// (Open-Meteo) both map onto it, so the UI looks the same for either source.
public enum WeatherConditionKind: String, Codable, CaseIterable, Sendable {
    case clear, mostlyClear, partlyCloudy, mostlyCloudy, cloudy
    case fog, haze, windy
    case drizzle, rain, heavyRain, freezingRain
    case sleet, snow, heavySnow, flurries
    case thunderstorm, hail

    /// Short text such as "Partly Cloudy".
    public var text: String {
        switch self {
        case .clear: "Clear"
        case .mostlyClear: "Mostly Clear"
        case .partlyCloudy: "Partly Cloudy"
        case .mostlyCloudy: "Mostly Cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .haze: "Haze"
        case .windy: "Windy"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy Rain"
        case .freezingRain: "Freezing Rain"
        case .sleet: "Sleet"
        case .snow: "Snow"
        case .heavySnow: "Heavy Snow"
        case .flurries: "Flurries"
        case .thunderstorm: "Thunderstorms"
        case .hail: "Hail"
        }
    }

    /// SF Symbol, with night variants where they exist. Use with multicolor rendering.
    public func symbolName(isDaylight: Bool = true) -> String {
        switch self {
        case .clear: isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: isDaylight ? "sun.max.fill" : "moon.fill"
        case .partlyCloudy: isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case .mostlyCloudy, .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .haze: isDaylight ? "sun.haze.fill" : "moon.haze.fill"
        case .windy: "wind"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: isDaylight ? "cloud.rain.fill" : "cloud.moon.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain, .sleet: "cloud.sleet.fill"
        case .snow, .flurries: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .hail: "cloud.hail.fill"
        }
    }

    /// What falls from the sky, for the animated background.
    public var precipitation: Precipitation {
        switch self {
        case .drizzle, .rain, .freezingRain: .rain
        case .heavyRain, .thunderstorm: .heavyRain
        case .sleet, .hail: .sleet
        case .snow, .flurries, .heavySnow: .snow
        default: .none
        }
    }

    /// How much of the sky is cloud, 0...1, for the animated background.
    public var cloudiness: Double {
        switch self {
        case .clear: 0
        case .mostlyClear: 0.15
        case .partlyCloudy, .windy, .haze: 0.4
        case .mostlyCloudy: 0.7
        default: 1
        }
    }

    public enum Precipitation: Sendable {
        case none, rain, heavyRain, sleet, snow
    }

    /// Maps a WMO weather interpretation code (used by Open-Meteo).
    /// Unknown codes fall back to cloudy.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 71, 85: self = .flurries
        case 73: self = .snow
        case 75, 86: self = .heavySnow
        case 77: self = .sleet
        case 95: self = .thunderstorm
        case 96, 99: self = .hail
        default: self = .cloudy
        }
    }
}
