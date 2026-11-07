import Foundation
import HomePadCore

/// Weather and time, available to everyone including guests.
enum InfoTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [weather(context), time(context)]
    }

    static func weather(_ context: ToolContext) -> AssistantTool {
        AssistantTool(name: "get_weather", description: "Current weather and today's high and low where the home is.") { _ in
            let service = try context.services.weather
            if service.current == nil { await service.refresh() }
            guard let weather = service.current else { return "Weather is not available right now." }
            context.emit(CardFactory.weather(weather))
            let unit = weather.unit == .celsius ? "C" : "F"
            var text = "\(weather.locationName): \(Int(weather.temperature.rounded()))°\(unit), \(weather.conditionText)."
            if let high = weather.high, let low = weather.low {
                text += " High \(Int(high.rounded()))°, low \(Int(low.rounded()))°."
            }
            let hours = weather.hourly.prefix(6).map { hour in
                "\(hour.date.formatted(date: .omitted, time: .shortened)) \(Int(hour.temperature.rounded()))°"
            }
            if !hours.isEmpty { text += " Next hours: " + hours.joined(separator: ", ") + "." }
            return text
        }
    }

    static func time(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "get_time",
            description: "Current date and time here, or in another city.",
            parameters: Schema.object(["city": Schema.string("City name for world time, for example Tokyo. Leave out for local time.")])
        ) { json in
            let city = ToolArguments(json).string("city")
            var zone = TimeZone.current
            if let city {
                guard let match = timeZone(forCity: city) else { return "HomePad does not know the time zone for \(city)." }
                zone = match
            }
            let formatter = DateFormatter()
            formatter.timeZone = zone
            formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
            return "\(city ?? "Here"): \(formatter.string(from: Date())) (\(zone.identifier))."
        }
    }

    /// Matches a city to a time zone identifier, for example "new york" to America/New_York.
    static func timeZone(forCity city: String) -> TimeZone? {
        let wanted = city.lowercased().replacingOccurrences(of: " ", with: "_")
        let identifier = TimeZone.knownTimeZoneIdentifiers.first { identifier in
            identifier.lowercased().split(separator: "/").last.map(String.init) == wanted
        }
        return identifier.flatMap(TimeZone.init(identifier:))
    }
}
