import Foundation
import HomePadCore

/// Calendar, reminders and memories. Every tool here needs a recognized member, so the
/// engine only offers them when personal content is unlocked.
enum PersonalTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [calendar(context), addReminder(context), addEvent(context), remember(context), forget(context)]
    }

    static func calendar(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "get_calendar",
            description: "The recognized person's calendar events and open reminders.",
            parameters: Schema.object([
                "start": Schema.string("First day, ISO 8601 date. Defaults to today."),
                "days": Schema.integer("How many days to include, 1 to 31. Defaults to 1."),
            ]),
            requiresRecognizedMember: true
        ) { json in
            let args = ToolArguments(json)
            let service = try context.services.calendar
            guard await hasAccess(service) else {
                return "HomePad does not have calendar access. It can be allowed in the Settings app."
            }
            let start = Calendar.current.startOfDay(for: args.date("start") ?? Date())
            let days = min(31, max(1, Int(args.double("days") ?? 1)))
            let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
            let events = await service.events(from: start, to: end).sorted { $0.start < $1.start }
            let reminders = days == 1 ? await service.reminders(includeCompleted: false) : []
            let items = events + reminders
            guard !items.isEmpty else { return "Nothing on the calendar for that time." }
            context.emit(CardFactory.calendar(items, title: days == 1 ? "Today" : "Next \(days) Days"))
            return items.map(describe).joined(separator: "\n")
        }
    }

    static func addReminder(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "add_reminder",
            description: "Add a reminder, a to-do or grocery items for the recognized person. "
                + "Several at once, such as a recipe's ingredients, go in items in one call.",
            parameters: Schema.object([
                "title": Schema.string("What to remember, for one reminder."),
                "items": [
                    "type": "array", "items": Schema.string("One item."),
                    "description": "Several items, each its own reminder, for example a recipe's ingredients for the Groceries list.",
                ],
                "due": Schema.string("Optional due date and time, ISO 8601 in local time."),
                "list": Schema.string("Optional list name, for example Groceries."),
            ]),
            requiresRecognizedMember: true
        ) { json in
            let args = ToolArguments(json)
            let titles = args.strings("items") + [args.string("title")].compactMap { $0 }
            guard !titles.isEmpty else { throw ToolError("Missing title or items.") }
            let service = try context.services.calendar
            guard await hasAccess(service) else { return "HomePad does not have reminders access." }
            for title in titles {
                try await service.addReminder(title: title, due: args.date("due"), listName: args.string("list"))
            }
            let what = titles.count == 1 ? "reminder \"\(titles[0])\"" : "\(titles.count) items (\(titles.joined(separator: "; ")))"
            return "Added \(what)" + (args.string("list").map { " to \($0)" } ?? "") + "."
        }
    }

    static func addEvent(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "add_event",
            description: "Add an event to the recognized person's calendar.",
            parameters: Schema.object([
                "title": Schema.string("Event title."),
                "start": Schema.string("Start date and time, ISO 8601 in local time."),
                "end": Schema.string("Optional end, ISO 8601. Defaults to one hour after the start."),
            ], required: ["title", "start"]),
            requiresRecognizedMember: true
        ) { json in
            let args = ToolArguments(json)
            let title = try args.requireString("title")
            guard let start = args.date("start") else { throw ToolError("The start time could not be read. Use ISO 8601.") }
            let end = args.date("end").flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
            let service = try context.services.calendar
            guard await hasAccess(service) else { return "HomePad does not have calendar access." }
            try await service.addEvent(title: title, start: start, end: end)
            let item = CalendarItem(id: UUID().uuidString, title: title, start: start, end: end)
            context.emit(CardFactory.calendar([item], title: "Added"))
            return "Added \(describe(item))."
        }
    }

    static func remember(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "remember_memory",
            description: "Save a fact, preference, or detail to remember about the recognized person, so it is remembered in future conversations.",
            parameters: Schema.object([
                "memory": Schema.string("The fact, preference, or detail to remember (e.g. 'Likes oat milk in coffee', 'Wakes up at 7am')."),
            ], required: ["memory"]),
            requiresRecognizedMember: true
        ) { json in
            let args = ToolArguments(json)
            let memory = try args.requireString("memory").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !memory.isEmpty else { throw ToolError("Missing memory text.") }
            let household = try context.services.household
            guard let member = household.unlockedMember ?? household.activeMember else {
                return "No recognized person is active. Memories are only stored for recognized household members."
            }
            var prefs = MemberAssistantPreferences(member: member)
            if !prefs.memories.contains(where: { $0.caseInsensitiveCompare(memory) == .orderedSame }) {
                prefs.memories.append(memory)
                if prefs.memories.count > MemberAssistantPreferences.memoryLimit {
                    prefs.memories.removeFirst(prefs.memories.count - MemberAssistantPreferences.memoryLimit)
                }
                household.update(prefs.applied(to: member))
            }
            return "Remembered for \(member.name): \"\(memory)\"."
        }
    }

    static func forget(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "forget_memory",
            description: "Remove or forget a previously remembered fact or preference for the recognized person.",
            parameters: Schema.object([
                "memory": Schema.string("The memory or keywords of the memory to forget."),
            ], required: ["memory"]),
            requiresRecognizedMember: true
        ) { json in
            let args = ToolArguments(json)
            let query = try args.requireString("memory").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { throw ToolError("Missing memory text.") }
            let household = try context.services.household
            guard let member = household.unlockedMember ?? household.activeMember else {
                return "No recognized person is active."
            }
            var prefs = MemberAssistantPreferences(member: member)
            let beforeCount = prefs.memories.count
            let removed = prefs.memories.filter { $0.lowercased().contains(query) }
            prefs.memories.removeAll { $0.lowercased().contains(query) }
            if prefs.memories.count < beforeCount {
                household.update(prefs.applied(to: member))
                return "Forgot for \(member.name): \(removed.map { "\"\($0)\"" }.joined(separator: ", "))."
            } else {
                return "Couldn't find any memory matching \"\(query)\" for \(member.name)."
            }
        }
    }

    /// Asks for calendar access the first time it is needed.
    @MainActor private static func hasAccess(_ service: any CalendarService) async -> Bool {
        if service.hasAccess { return true }
        return await service.requestAccess()
    }

    private static func describe(_ item: CalendarItem) -> String {
        if item.isReminder { return "Reminder: \(item.title)" }
        if item.isAllDay { return "\(item.title), all day \(item.start.formatted(date: .abbreviated, time: .omitted))" }
        let range = "\(item.start.formatted(date: .abbreviated, time: .shortened)) to \(item.end.formatted(date: .omitted, time: .shortened))"
        return "\(item.title), \(range)" + (item.location.map { " at \($0)" } ?? "")
    }
}
