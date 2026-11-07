import Foundation
import HomePadCore

/// Curated unit choices. Forecasts are stored in metric and converted for display.
public enum WeatherUnitSystem: String, Codable, CaseIterable, Sendable {
    case automatic
    case us
    case metric

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .us: "°F, mph"
        case .metric: "°C, km/h"
        }
    }

    /// True for US units after resolving `automatic` against the iPad's region.
    public func usesUSUnits(locale: Locale = .current) -> Bool {
        switch self {
        case .automatic: locale.measurementSystem == .us
        case .us: true
        case .metric: false
        }
    }

    public func temperatureUnit(locale: Locale = .current) -> TemperatureUnit {
        usesUSUnits(locale: locale) ? .fahrenheit : .celsius
    }

    /// Converts a Celsius value to the display unit.
    public func temperature(_ celsius: Double, locale: Locale = .current) -> Double {
        usesUSUnits(locale: locale) ? celsius * 9 / 5 + 32 : celsius
    }

    /// "54°", rounded, in the display unit.
    public func temperatureText(_ celsius: Double, locale: Locale = .current) -> String {
        "\(Int(temperature(celsius, locale: locale).rounded()))°"
    }

    /// "12 mph" or "19 km/h".
    public func windText(_ kph: Double, locale: Locale = .current) -> String {
        usesUSUnits(locale: locale) ? "\(Int((kph / 1.609344).rounded())) mph" : "\(Int(kph.rounded())) km/h"
    }
}
