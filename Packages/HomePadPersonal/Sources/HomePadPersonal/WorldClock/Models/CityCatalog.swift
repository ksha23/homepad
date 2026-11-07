import Foundation

/// Offline city lookup for the World Clock and the assistant's world_time tool.
/// Every IANA zone city ("Chicago", "Kolkata") is searchable, plus aliases for
/// big cities that are not zone names ("San Francisco", "Beijing", "Mumbai").
public enum CityCatalog {
    /// Well-known cities that share a zone with a differently named city.
    static let aliases: [String: String] = [
        "San Francisco": "America/Los_Angeles", "Seattle": "America/Los_Angeles", "San Diego": "America/Los_Angeles",
        "Portland": "America/Los_Angeles", "Las Vegas": "America/Los_Angeles", "Salt Lake City": "America/Denver",
        "Austin": "America/Chicago", "Dallas": "America/Chicago", "Houston": "America/Chicago", "Madison": "America/Chicago",
        "Milwaukee": "America/Chicago", "Minneapolis": "America/Chicago", "Atlanta": "America/New_York",
        "Boston": "America/New_York", "Miami": "America/New_York", "Washington": "America/New_York",
        "Philadelphia": "America/New_York", "Montreal": "America/Toronto", "Beijing": "Asia/Shanghai",
        "Shenzhen": "Asia/Shanghai", "Mumbai": "Asia/Kolkata", "New Delhi": "Asia/Kolkata", "Delhi": "Asia/Kolkata",
        "Bangalore": "Asia/Kolkata", "Osaka": "Asia/Tokyo", "Kyoto": "Asia/Tokyo", "Munich": "Europe/Berlin",
        "Frankfurt": "Europe/Berlin", "Barcelona": "Europe/Madrid", "Milan": "Europe/Rome", "Geneva": "Europe/Zurich",
        "Edinburgh": "Europe/London", "Manchester": "Europe/London", "Hanoi": "Asia/Bangkok", "Melbourne": "Australia/Melbourne",
        "Wellington": "Pacific/Auckland", "Honolulu": "Pacific/Honolulu", "Rio de Janeiro": "America/Sao_Paulo",
        "Cape Town": "Africa/Johannesburg", "Tel Aviv": "Asia/Jerusalem", "Abu Dhabi": "Asia/Dubai",
    ]

    /// Every searchable city, alphabetically.
    public static let all: [WorldClockCity] = {
        var cities: [String: WorldClockCity] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let parts = identifier.split(separator: "/")
            guard parts.count >= 2, let last = parts.last, !identifier.hasPrefix("Etc/") else { continue }
            let name = last.replacingOccurrences(of: "_", with: " ")
            cities[name] = cities[name] ?? WorldClockCity(name: name, timeZoneID: identifier)
        }
        for (name, identifier) in aliases where TimeZone(identifier: identifier) != nil {
            cities[name] = WorldClockCity(name: name, timeZoneID: identifier)
        }
        return cities.values.sorted { $0.name < $1.name }
    }()

    /// Cities whose name starts with, then contains, the query.
    public static func search(_ query: String, limit: Int = 30) -> [WorldClockCity] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        let prefix = all.filter { normalized($0.name).hasPrefix(needle) }
        let contains = all.filter { !normalized($0.name).hasPrefix(needle) && normalized($0.name).contains(needle) }
        return Array((prefix + contains).prefix(limit))
    }

    /// The single best match for spoken input ("what time is it in tokyo").
    public static func bestMatch(_ query: String) -> WorldClockCity? {
        let needle = normalized(query)
        return all.first { normalized($0.name) == needle } ?? search(query, limit: 1).first
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
