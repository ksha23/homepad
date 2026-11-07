import Foundation

/// Where the weather is for. Coordinates in degrees.
public struct WeatherPlace: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// IANA identifier such as "America/Chicago", when known.
    public var timeZoneID: String?

    public init(name: String, latitude: Double, longitude: Double, timeZoneID: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
    }
}

/// Where the household wants weather for. Chosen in Settings or in the Weather app.
public enum WeatherLocationChoice: Codable, Hashable, Sendable {
    /// Nobody chose yet. The Weather app asks before requesting location access.
    case undecided
    /// The iPad's location (Core Location, when-in-use).
    case current
    /// A city picked by search.
    case place(WeatherPlace)
}
