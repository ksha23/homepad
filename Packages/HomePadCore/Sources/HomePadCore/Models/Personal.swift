import Foundation

/// A running or finished timer. Timers are household-wide, not personal.
public struct HomeTimer: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case running, paused, finished }

    public var id: UUID
    public var label: String
    public var duration: TimeInterval
    public var status: Status
    /// Set while running.
    public var endDate: Date?
    /// Set while paused.
    public var remainingWhenPaused: TimeInterval?

    public init(id: UUID = UUID(), label: String, duration: TimeInterval, status: Status = .running,
                endDate: Date? = nil, remainingWhenPaused: TimeInterval? = nil) {
        self.id = id
        self.label = label
        self.duration = duration
        self.status = status
        self.endDate = endDate ?? (status == .running ? Date().addingTimeInterval(duration) : nil)
        self.remainingWhenPaused = remainingWhenPaused
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        switch status {
        case .running: max(0, (endDate ?? now).timeIntervalSince(now))
        case .paused: remainingWhenPaused ?? duration
        case .finished: 0
        }
    }
}

public struct CalendarItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var calendarName: String?
    public var colorHex: String?
    public var isReminder: Bool
    /// From a calendar or list shared with the whole household (guests included).
    public var isShared: Bool
    /// Reminders only.
    public var isCompleted: Bool
    /// The reminders list or calendar it belongs to.
    public var listID: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                location: String? = nil, calendarName: String? = nil, colorHex: String? = nil,
                isReminder: Bool = false, isShared: Bool = false, isCompleted: Bool = false,
                listID: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarName = calendarName
        self.colorHex = colorHex
        self.isReminder = isReminder
        self.isShared = isShared
        self.isCompleted = isCompleted
        self.listID = listID
    }
}

/// A reminders list as other modules see it.
public struct ReminderListInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var colorHex: String?
    public var isShared: Bool

    public init(id: String, title: String, colorHex: String? = nil, isShared: Bool = false) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.isShared = isShared
    }
}

/// A named place to ask the weather for, such as a world city a face shows.
public struct WeatherLocation: Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// IANA identifier such as "Europe/London", when known.
    public var timeZoneID: String?

    public init(name: String, latitude: Double, longitude: Double, timeZoneID: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
    }
}

public struct WeatherSnapshot: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public var date: Date
        public var temperature: Double
        public var symbolName: String
        public init(date: Date, temperature: Double, symbolName: String) {
            self.date = date
            self.temperature = temperature
            self.symbolName = symbolName
        }
    }

    public struct Day: Equatable, Sendable {
        public var date: Date
        public var high: Double
        public var low: Double
        public var symbolName: String
        /// 0...1
        public var precipitationChance: Double?
        public init(date: Date, high: Double, low: Double, symbolName: String, precipitationChance: Double? = nil) {
            self.date = date
            self.high = high
            self.low = low
            self.symbolName = symbolName
            self.precipitationChance = precipitationChance
        }
    }

    public var locationName: String
    public var temperature: Double
    public var high: Double?
    public var low: Double?
    public var conditionText: String
    public var symbolName: String
    public var unit: TemperatureUnit
    public var hourly: [Hour]
    public var daily: [Day]
    public var updatedAt: Date
    /// Today's sunrise and sunset at the forecast location, when the source has them.
    public var sunrise: Date?
    public var sunset: Date?
    /// True while the sun is up at the forecast location. Nil when unknown.
    public var isDaylight: Bool?

    public init(locationName: String, temperature: Double, high: Double? = nil, low: Double? = nil,
                conditionText: String, symbolName: String, unit: TemperatureUnit = .fahrenheit,
                hourly: [Hour] = [], daily: [Day] = [], updatedAt: Date = Date(),
                sunrise: Date? = nil, sunset: Date? = nil, isDaylight: Bool? = nil) {
        self.locationName = locationName
        self.temperature = temperature
        self.high = high
        self.low = low
        self.conditionText = conditionText
        self.symbolName = symbolName
        self.unit = unit
        self.hourly = hourly
        self.daily = daily
        self.updatedAt = updatedAt
        self.sunrise = sunrise
        self.sunset = sunset
        self.isDaylight = isDaylight
    }
}
