import Foundation

/// Which service produced a forecast.
public enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case openMeteo
    case demo

    public var displayName: String {
        switch self {
        case .weatherKit: "Apple Weather"
        case .openMeteo: "Open-Meteo"
        case .demo: "Demo"
        }
    }
}

/// A full forecast in canonical metric units (degrees Celsius, km/h, mm).
/// Views convert to the household's units with `WeatherUnitSystem`.
public struct WeatherForecast: Codable, Equatable, Sendable {
    public var place: WeatherPlace
    public var current: CurrentConditions
    /// Next 24 to 48 hours, starting with the current hour.
    public var hourly: [HourlyForecast]
    /// Today first, up to 10 days.
    public var daily: [DailyForecast]
    public var source: WeatherSource
    public var fetchedAt: Date

    public init(place: WeatherPlace, current: CurrentConditions, hourly: [HourlyForecast], daily: [DailyForecast],
                source: WeatherSource, fetchedAt: Date = Date()) {
        self.place = place
        self.current = current
        self.hourly = hourly
        self.daily = daily
        self.source = source
        self.fetchedAt = fetchedAt
    }

    /// Today's forecast, if the daily list covers it.
    public var today: DailyForecast? { daily.first }

    /// The hours from `now` on, for strips that label the first one "Now". Hours
    /// that already ended are dropped, since a forecast can be half an hour old,
    /// and the current hour shows the current conditions, as Apple's Weather app
    /// does. Otherwise "Now" after sunset could show the sunny hour before.
    public func upcomingHours(at now: Date) -> [HourlyForecast] {
        var hours = hourly.filter { $0.date.addingTimeInterval(3600) > now }
        guard var first = hours.first, first.date <= now else { return hours }
        first.temperature = current.temperature
        first.condition = current.condition
        first.isDaylight = current.isDaylight
        first.windSpeed = current.windSpeed ?? first.windSpeed
        hours[0] = first
        return hours
    }

    /// The location's time zone, falling back to the iPad's.
    public var timeZone: TimeZone {
        place.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}

public struct CurrentConditions: Codable, Equatable, Sendable {
    public var date: Date
    public var temperature: Double
    public var apparentTemperature: Double?
    public var condition: WeatherConditionKind
    public var isDaylight: Bool
    /// 0...1
    public var humidity: Double?
    public var windSpeed: Double?
    /// Degrees the wind comes from, 0 = north.
    public var windDirection: Double?
    public var windGust: Double?
    public var uvIndex: Double?
    /// Sea-level pressure in hPa.
    public var pressure: Double?
    /// 0...1
    public var cloudCover: Double?
    public var precipitation: Double?

    public init(date: Date, temperature: Double, apparentTemperature: Double? = nil, condition: WeatherConditionKind,
                isDaylight: Bool = true, humidity: Double? = nil, windSpeed: Double? = nil, windDirection: Double? = nil,
                windGust: Double? = nil, uvIndex: Double? = nil, pressure: Double? = nil, cloudCover: Double? = nil,
                precipitation: Double? = nil) {
        self.date = date
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.isDaylight = isDaylight
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGust = windGust
        self.uvIndex = uvIndex
        self.pressure = pressure
        self.cloudCover = cloudCover
        self.precipitation = precipitation
    }
}

public struct HourlyForecast: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var temperature: Double
    public var condition: WeatherConditionKind
    public var isDaylight: Bool
    /// 0...1
    public var precipitationChance: Double?
    public var windSpeed: Double?

    public init(date: Date, temperature: Double, condition: WeatherConditionKind, isDaylight: Bool = true,
                precipitationChance: Double? = nil, windSpeed: Double? = nil) {
        self.date = date
        self.temperature = temperature
        self.condition = condition
        self.isDaylight = isDaylight
        self.precipitationChance = precipitationChance
        self.windSpeed = windSpeed
    }
}

public struct DailyForecast: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { date }
    /// Midnight at the forecast location.
    public var date: Date
    public var high: Double
    public var low: Double
    public var condition: WeatherConditionKind
    /// 0...1
    public var precipitationChance: Double?
    public var precipitationAmount: Double?
    public var sunrise: Date?
    public var sunset: Date?
    public var uvIndexMax: Double?
    public var windSpeedMax: Double?

    public init(date: Date, high: Double, low: Double, condition: WeatherConditionKind, precipitationChance: Double? = nil,
                precipitationAmount: Double? = nil, sunrise: Date? = nil, sunset: Date? = nil,
                uvIndexMax: Double? = nil, windSpeedMax: Double? = nil) {
        self.date = date
        self.high = high
        self.low = low
        self.condition = condition
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
        self.sunrise = sunrise
        self.sunset = sunset
        self.uvIndexMax = uvIndexMax
        self.windSpeedMax = windSpeedMax
    }
}
