import Foundation
import HomePadCore

/// A city the World Clock face can show. The list is curated, like the
/// city picker on Apple Watch, so names read well and time zones are right.
struct WorldCity: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let timeZoneID: String
    /// Where the city is, for its weather.
    let latitude: Double
    let longitude: Double

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// The city as a place to ask the weather for.
    var weatherLocation: WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude, timeZoneID: timeZoneID)
    }

    static func city(_ id: String) -> WorldCity? {
        all.first { $0.id == id }
    }

    static let all: [WorldCity] = [
        WorldCity(id: "honolulu", name: "Honolulu", timeZoneID: "Pacific/Honolulu", latitude: 21.31, longitude: -157.86),
        WorldCity(id: "anchorage", name: "Anchorage", timeZoneID: "America/Anchorage", latitude: 61.22, longitude: -149.9),
        WorldCity(id: "los-angeles", name: "Los Angeles", timeZoneID: "America/Los_Angeles", latitude: 34.05, longitude: -118.24),
        WorldCity(id: "cupertino", name: "Cupertino", timeZoneID: "America/Los_Angeles", latitude: 37.32, longitude: -122.03),
        WorldCity(id: "denver", name: "Denver", timeZoneID: "America/Denver", latitude: 39.74, longitude: -104.99),
        WorldCity(id: "chicago", name: "Chicago", timeZoneID: "America/Chicago", latitude: 41.88, longitude: -87.63),
        WorldCity(id: "madison", name: "Madison", timeZoneID: "America/Chicago", latitude: 43.07, longitude: -89.4),
        WorldCity(id: "mexico-city", name: "Mexico City", timeZoneID: "America/Mexico_City", latitude: 19.43, longitude: -99.13),
        WorldCity(id: "toronto", name: "Toronto", timeZoneID: "America/Toronto", latitude: 43.65, longitude: -79.38),
        WorldCity(id: "new-york", name: "New York", timeZoneID: "America/New_York", latitude: 40.71, longitude: -74.01),
        WorldCity(id: "sao-paulo", name: "São Paulo", timeZoneID: "America/Sao_Paulo", latitude: -23.55, longitude: -46.63),
        WorldCity(id: "reykjavik", name: "Reykjavík", timeZoneID: "Atlantic/Reykjavik", latitude: 64.15, longitude: -21.94),
        WorldCity(id: "london", name: "London", timeZoneID: "Europe/London", latitude: 51.51, longitude: -0.13),
        WorldCity(id: "lisbon", name: "Lisbon", timeZoneID: "Europe/Lisbon", latitude: 38.72, longitude: -9.14),
        WorldCity(id: "paris", name: "Paris", timeZoneID: "Europe/Paris", latitude: 48.86, longitude: 2.35),
        WorldCity(id: "berlin", name: "Berlin", timeZoneID: "Europe/Berlin", latitude: 52.52, longitude: 13.4),
        WorldCity(id: "rome", name: "Rome", timeZoneID: "Europe/Rome", latitude: 41.9, longitude: 12.5),
        WorldCity(id: "cairo", name: "Cairo", timeZoneID: "Africa/Cairo", latitude: 30.04, longitude: 31.24),
        WorldCity(id: "nairobi", name: "Nairobi", timeZoneID: "Africa/Nairobi", latitude: -1.29, longitude: 36.82),
        WorldCity(id: "istanbul", name: "Istanbul", timeZoneID: "Europe/Istanbul", latitude: 41.01, longitude: 28.98),
        WorldCity(id: "dubai", name: "Dubai", timeZoneID: "Asia/Dubai", latitude: 25.2, longitude: 55.27),
        WorldCity(id: "mumbai", name: "Mumbai", timeZoneID: "Asia/Kolkata", latitude: 19.08, longitude: 72.88),
        WorldCity(id: "bangkok", name: "Bangkok", timeZoneID: "Asia/Bangkok", latitude: 13.76, longitude: 100.5),
        WorldCity(id: "singapore", name: "Singapore", timeZoneID: "Asia/Singapore", latitude: 1.35, longitude: 103.82),
        WorldCity(id: "shanghai", name: "Shanghai", timeZoneID: "Asia/Shanghai", latitude: 31.23, longitude: 121.47),
        WorldCity(id: "hong-kong", name: "Hong Kong", timeZoneID: "Asia/Hong_Kong", latitude: 22.32, longitude: 114.17),
        WorldCity(id: "taipei", name: "Taipei", timeZoneID: "Asia/Taipei", latitude: 25.03, longitude: 121.57),
        WorldCity(id: "seoul", name: "Seoul", timeZoneID: "Asia/Seoul", latitude: 37.57, longitude: 126.98),
        WorldCity(id: "tokyo", name: "Tokyo", timeZoneID: "Asia/Tokyo", latitude: 35.68, longitude: 139.69),
        WorldCity(id: "sydney", name: "Sydney", timeZoneID: "Australia/Sydney", latitude: -33.87, longitude: 151.21),
        WorldCity(id: "auckland", name: "Auckland", timeZoneID: "Pacific/Auckland", latitude: -36.85, longitude: 174.76),
    ]

    /// Hours between this city and another time zone at a moment, for example +6 or -3.5.
    func hoursAhead(of other: TimeZone, at date: Date) -> Double {
        Double(timeZone.secondsFromGMT(for: date) - other.secondsFromGMT(for: date)) / 3600
    }

    /// "Today, +6 hrs", "Tomorrow, +15 hrs" or "Same time".
    func relativeLabel(from other: TimeZone, at date: Date) -> String {
        let hours = hoursAhead(of: other, at: date)
        let day = Self.dayWord(cityDay: dayStamp(in: timeZone, date: date), localDay: dayStamp(in: other, date: date))
        guard hours != 0 else { return "\(day), same time" }
        let amount = hours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))
        let unit = abs(hours) == 1 ? "hr" : "hrs"
        return "\(day), \(hours > 0 ? "+" : "-")\(amount) \(unit)"
    }

    /// True between 7 PM and 6 AM in the city, when its dial turns dark.
    func isNight(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour >= 19 || hour < 6
    }

    /// The calendar date in a zone as a sortable number such as 20261021.
    private func dayStamp(in zone: TimeZone, date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    private static func dayWord(cityDay: Int, localDay: Int) -> String {
        if cityDay > localDay { return "Tomorrow" }
        if cityDay < localDay { return "Yesterday" }
        return "Today"
    }
}
