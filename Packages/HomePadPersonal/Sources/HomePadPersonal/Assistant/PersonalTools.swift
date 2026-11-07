import Foundation
import HomePadCore

/// Assistant tools for forecasts, reminders and world time. The generic
/// get_weather, get_calendar, add_reminder and add_event tools belong to the
/// Assistant module and work through `services.weather` and `services.calendar`.
@MainActor
enum PersonalTools {
    static func make(personal: PersonalServices) -> [AssistantTool] {
        [dailyForecast(personal.weather), listReminders(personal.calendar), completeReminder(personal.calendar), worldTime(personal.clocks)]
    }

    static func dailyForecast(_ weather: PersonalWeatherService) -> AssistantTool {
        AssistantTool(
            name: "get_daily_forecast",
            description: "Daily weather forecast for the household's location: conditions, high and low, chance of precipitation. Use for questions about tomorrow, the weekend or the coming days.",
            parameters: Schema.object(["days": Schema.integer("How many days to include, starting today. 1 to 10. Defaults to 3.")])
        ) { arguments in
            if weather.isStale { await weather.refresh() }
            guard let forecast = weather.forecast else { return "Weather is not set up yet. Choose a location in the Weather app." }
            let count = min(max(arguments["days"]?.intValue ?? 3, 1), 10)
            return ForecastSummary.daily(forecast, days: count, units: weather.units)
        }
    }

    static func listReminders(_ calendar: HouseholdCalendarService) -> AssistantTool {
        AssistantTool(
            name: "list_reminders",
            description: "Lists open reminders the recognized person may see, optionally from one list such as Groceries.",
            parameters: Schema.object([
                "list": Schema.string("Reminders list name, for example Groceries. Omit for all lists."),
                "include_completed": Schema.boolean("Include completed reminders. Defaults to false."),
            ]),
            requiresRecognizedMember: true
        ) { arguments in
            guard calendar.hasReminderAccess else { return PersonalError.noReminderAccess.localizedDescription }
            let listName = arguments["list"]?.stringValue
            var listID: String?
            if let listName {
                guard let list = calendar.visibleReminderLists.first(where: { $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame }) else {
                    return PersonalError.listNotFound(listName).localizedDescription
                }
                listID = list.id
            }
            let items = await calendar.reminderItems(listID: listID, includeCompleted: arguments["include_completed"]?.boolValue ?? false)
            guard !items.isEmpty else { return listName.map { "\($0) is empty." } ?? "There are no open reminders." }
            return items.map { item in
                var line = "- \(item.title) (\(item.listTitle)"
                if let due = item.due { line += ", due \(due.formatted(date: .abbreviated, time: item.dueHasTime ? .shortened : .omitted))" }
                if item.isCompleted { line += ", done" }
                return line + ")"
            }.joined(separator: "\n")
        }
    }

    static func completeReminder(_ calendar: HouseholdCalendarService) -> AssistantTool {
        AssistantTool(
            name: "complete_reminder",
            description: "Checks off an open reminder by its title, for example \"I bought the milk\".",
            parameters: Schema.object([
                "title": Schema.string("Title of the reminder, or a close match."),
                "list": Schema.string("Reminders list to look in. Optional."),
            ], required: ["title"]),
            requiresRecognizedMember: true
        ) { arguments in
            guard let title = arguments["title"]?.stringValue, !title.isEmpty else { return "Which reminder should I check off?" }
            let listName = arguments["list"]?.stringValue
            let items = await calendar.reminderItems().filter { item in
                listName.map { item.listTitle.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true
            }
            guard let match = ReminderMatcher.bestMatch(for: title, in: items) else {
                return "I could not find an open reminder called \(title)."
            }
            try calendar.setCompleted(match, true)
            return "Checked off \(match.title) in \(match.listTitle)."
        }
    }

    static func worldTime(_ clocks: WorldClockStore) -> AssistantTool {
        AssistantTool(
            name: "world_time",
            description: "Current local time in a city anywhere in the world, and how far ahead or behind home it is.",
            parameters: Schema.object(["city": Schema.string("City name, for example Tokyo or San Francisco.")], required: ["city"])
        ) { arguments in
            guard let name = arguments["city"]?.stringValue, !name.isEmpty else { return "Which city?" }
            var city = clocks.lookup(name)
            if city == nil, let result = await PlaceSearch.search(name).first, let zone = result.place.timeZoneID {
                city = WorldClockCity(name: result.place.name, timeZoneID: zone)
            }
            guard let city else { return "I don't know the time zone for \(name)." }
            return ForecastSummary.worldTime(city: city, at: Date())
        }
    }
}
