import Foundation
import HomePadCore

/// Assistant tools for the recognized person's wake-up alarms: "set an alarm
/// for 7", "turn off my alarms" and "what alarms do I have". Alarms are
/// personal, so every tool needs a recognized member and acts on theirs only.
@MainActor
enum AlarmTools {
    static func make(service: AlarmService, household: Household, clock: @escaping () -> Date = Date.init) -> [AssistantTool] {
        [setAlarm(service, household, clock), turnOffAlarms(service, household), listAlarms(service, household, clock)]
    }

    private static let notRecognized = "Alarms are personal. Ask the person to look at the screen so HomePad recognizes them."

    /// The member at the screen, once recognized.
    private static func owner(_ household: Household) -> UUID? {
        household.isPersonalContentUnlocked ? household.activeMember?.id : nil
    }

    static func setAlarm(_ service: AlarmService, _ household: Household, _ clock: @escaping () -> Date) -> AssistantTool {
        AssistantTool(
            name: "set_alarm",
            description: "Set a wake-up alarm for the recognized person. A time said without AM or PM, like \"set an alarm for 7\", means the morning unless they say evening or night.",
            parameters: Schema.object([
                "hour": Schema.integer("Hour in 24-hour time, 0 to 23. 7 is 7 AM and 19 is 7 PM."),
                "minute": Schema.integer("Minute, 0 to 59. Defaults to 0."),
                "label": Schema.string("A short name, for example Gym. Optional."),
                "repeat": Schema.string("The days it repeats: once, every day, weekdays, weekends, or day names such as \"monday, wednesday\". Defaults to once."),
            ], required: ["hour"]),
            requiresRecognizedMember: true
        ) { arguments in
            guard let ownerID = owner(household) else { return notRecognized }
            guard let hour = arguments["hour"]?.intValue, (0...23).contains(hour) else { return "An alarm needs an hour from 0 to 23." }
            let minute = arguments["minute"]?.intValue ?? 0
            guard (0...59).contains(minute) else { return "The minute must be from 0 to 59." }
            guard let weekdays = AlarmRepeatParser.weekdays(from: arguments["repeat"]?.stringValue ?? "once") else {
                return "I could not tell which days it repeats. Say once, every day, weekdays, weekends, or the days."
            }
            let label = arguments["label"]?.stringValue ?? ""
            // The same time and days already set: turn that one on instead of adding a twin.
            var alarm = service.alarms(ownedBy: ownerID).first { $0.hour == hour && $0.minute == minute && $0.weekdays == weekdays }
                ?? HomeAlarm(ownerID: ownerID, hour: hour, minute: minute, label: label, weekdays: weekdays)
            if !label.isEmpty { alarm.label = label }
            alarm.isEnabled = true
            if service.alarms.contains(where: { $0.id == alarm.id }) { service.update(alarm) } else { service.add(alarm) }
            let now = clock()
            var reply = "Alarm set for \(AlarmFormat.time(alarm))"
            if alarm.repeats { reply += ", \(AlarmFormat.repeatText(alarm.weekdays).lowercased())" }
            if let next = service.upcoming[alarm.id] {
                reply += ". It rings \(AlarmFormat.when(next, from: now)), \(AlarmFormat.countdown(to: next, from: now))"
            }
            return reply + "."
        }
    }

    static func turnOffAlarms(_ service: AlarmService, _ household: Household) -> AssistantTool {
        AssistantTool(
            name: "turn_off_alarms",
            description: "Turn off the recognized person's alarms: all of them, or the ones at an hour or with a label. If one of their alarms is ringing, this stops it instead and it still rings next time.",
            parameters: Schema.object([
                "hour": Schema.integer("Only alarms at this hour, 0 to 23. Optional."),
                "minute": Schema.integer("Only alarms at this minute, with hour. Optional."),
                "label": Schema.string("Only alarms whose label contains this. Optional."),
            ]),
            requiresRecognizedMember: true
        ) { arguments in
            guard let ownerID = owner(household) else { return notRecognized }
            let mine = service.alarms(ownedBy: ownerID)
            let ringing = mine.filter { service.ringing[$0.id] != nil }
            if !ringing.isEmpty {
                ringing.forEach { service.stop($0.id) }
                return ringing.count == 1 ? "Stopped your \(AlarmFormat.time(ringing[0])) alarm." : "Stopped \(ringing.count) alarms."
            }
            let hour = arguments["hour"]?.intValue
            let minute = arguments["minute"]?.intValue
            let label = arguments["label"]?.stringValue?.lowercased()
            let matches = mine.filter { alarm in
                alarm.isEnabled
                    && hour.map { alarm.hour == $0 } ?? true
                    && minute.map { alarm.minute == $0 } ?? true
                    && label.map { alarm.title.lowercased().contains($0) } ?? true
            }
            guard !matches.isEmpty else { return mine.contains(where: \.isEnabled) ? "No alarm of yours matches that." : "All your alarms are already off." }
            matches.forEach { service.setEnabled($0.id, false) }
            return matches.count == 1 ? "Turned off your \(AlarmFormat.time(matches[0])) alarm." : "Turned off \(matches.count) alarms."
        }
    }

    static func listAlarms(_ service: AlarmService, _ household: Household, _ clock: @escaping () -> Date) -> AssistantTool {
        AssistantTool(
            name: "list_alarms",
            description: "List the recognized person's alarms, which are on, and when the next one rings.",
            requiresRecognizedMember: true
        ) { _ in
            guard let ownerID = owner(household) else { return notRecognized }
            let mine = service.alarms(ownedBy: ownerID)
            guard !mine.isEmpty else { return "You have no alarms." }
            let now = clock()
            return mine.map { alarm in
                var line = "- \(AlarmFormat.time(alarm)), \(alarm.title), \(AlarmFormat.repeatText(alarm.weekdays).lowercased())"
                if let next = service.upcoming[alarm.id] {
                    line += ", on, rings \(AlarmFormat.when(next, from: now))"
                } else {
                    line += ", off"
                }
                return line
            }.joined(separator: "\n")
        }
    }
}

/// Reads "weekdays", "every day", "mon, wed and fri" or "once" into days.
enum AlarmRepeatParser {
    /// Nil when a word is not a day or a known phrase.
    static func weekdays(from text: String) -> Set<Locale.Weekday>? {
        let phrase = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch phrase {
        case "", "once", "never", "one time", "no": return []
        case "every day", "everyday", "daily", "all days", "each day": return Set(Locale.Weekday.ordered)
        case "weekdays", "every weekday", "workdays", "work days": return Locale.Weekday.workweek
        case "weekends", "every weekend", "weekend": return Locale.Weekday.weekend
        default: break
        }
        let words = phrase.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty && $0 != "and" && $0 != "every" }
        var days: Set<Locale.Weekday> = []
        for word in words {
            guard let day = dayNames.first(where: { word.hasPrefix($0.key) })?.value else { return nil }
            days.insert(day)
        }
        return days.isEmpty ? nil : days
    }

    private static let dayNames: [String: Locale.Weekday] = [
        "sun": .sunday, "mon": .monday, "tue": .tuesday, "wed": .wednesday,
        "thu": .thursday, "fri": .friday, "sat": .saturday,
    ]
}
