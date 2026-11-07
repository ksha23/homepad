import Foundation
import HomePadCore

/// Live facts that go into the system prompt for each request.
struct PromptContext: Sendable {
    var now: Date
    var timeZone: TimeZone
    var locationName: String?
    var weather: String?
    var memberName: String?
    var aboutMember: String?
    var memberMemories: [String]
    var currentVolume: Double?
    var isPersonalUnlocked: Bool
    var personality: Personality
    /// Rooms with their devices and states, one line per room.
    var homeLines: [String]
    var toolNames: [String]
    /// The small on-device model gets a shorter prompt.
    var compact: Bool
    /// What is on screen (`ScreenContextReader`), so "this" and "these" mean something.
    var screen: String?
    /// The answer shows in HomePad's big type, which bolds the key facts, as on HomeView.
    var marksKeyFacts: Bool

    init(
        now: Date, timeZone: TimeZone, locationName: String? = nil, weather: String? = nil,
        memberName: String? = nil, aboutMember: String? = nil, memberMemories: [String] = [],
        currentVolume: Double? = nil, isPersonalUnlocked: Bool, personality: Personality,
        homeLines: [String] = [], toolNames: [String] = [], compact: Bool = false,
        screen: String? = nil, marksKeyFacts: Bool = false
    ) {
        self.now = now
        self.timeZone = timeZone
        self.locationName = locationName
        self.weather = weather
        self.memberName = memberName
        self.aboutMember = aboutMember
        self.memberMemories = memberMemories
        self.currentVolume = currentVolume
        self.isPersonalUnlocked = isPersonalUnlocked
        self.personality = personality
        self.homeLines = homeLines
        self.toolNames = toolNames
        self.compact = compact
        self.screen = screen
        self.marksKeyFacts = marksKeyFacts
    }
}

/// Writes the system prompt. Answers are spoken and shown in big type, so the
/// rules favor short plain sentences and honest tool use.
enum SystemPromptBuilder {
    static func build(_ context: PromptContext) -> String {
        var sections: [String] = [
            """
            You are HomePad, the voice assistant on a smart home display in someone's home. \
            \(style(marksKeyFacts: context.marksKeyFacts)) \(context.personality.instruction)
            """,
            """
            Use the tools to see and control the home, timers, music and calendars. Never say you did \
            something unless a tool confirmed it. To change several devices, call control_device once \
            with several actions. If a request is unclear, ask one short question, but act on open requests \
            such as "play some music" by choosing something that fits instead of asking. \
            When asked to turn the volume up or down without a specific number, adjust mildly by 5% to 10% \
            (e.g. +7% or -7%). If asked to turn it way up or a lot, use best judgement (e.g. +20% to +30%). \
            Never jump directly to 75% unless the user asked for 75%. \
            When the recognized user asks you to remember something, or shares a personal preference or detail \
            about themselves, use remember_memory to save it. Use forget_memory if they ask to forget something.
            """,
        ]
        sections.append(facts(context).joined(separator: "\n"))
        if let screen = context.screen {
            sections.append(screenSection(screen, compact: context.compact))
        }
        if !context.homeLines.isEmpty {
            sections.append("Home:\n" + context.homeLines.joined(separator: "\n"))
        }
        if !context.compact, !context.toolNames.isEmpty {
            sections.append("Tools available: " + context.toolNames.joined(separator: ", ") + ".")
        }
        return sections.joined(separator: "\n\n")
    }

    /// Plain sentences, with the few facts that answer the question in bold when
    /// the answer shows in HomePad's own big type. Speech drops the marks.
    private static func style(marksKeyFacts: Bool) -> String {
        guard marksKeyFacts else {
            return "Answers are read aloud and shown in large type, so use plain sentences without markdown, lists or emoji unless asked."
        }
        return """
            Answers are read aloud and shown in large type, so use plain sentences without lists or emoji unless asked. \
            Put the one to three facts that answer the question in Markdown bold, for example "**No**, it comes from \
            **ancient Rome**." or "It was invented in **1842** by **Sir John Herschel**." Bold nothing else and use no other Markdown.
            """
    }

    private static func facts(_ context: PromptContext) -> [String] {
        let formatter = DateFormatter()
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        var lines = ["Now: \(formatter.string(from: context.now)) (\(context.timeZone.identifier))."]
        if let location = context.locationName { lines.append("Location: \(location).") }
        if let weather = context.weather { lines.append("Weather: \(weather).") }
        if let volume = context.currentVolume { lines.append("Current volume: \(Int((volume * 100).rounded()))%.") }
        if let name = context.memberName {
            lines.append(context.isPersonalUnlocked
                ? "Speaking with: \(name), recognized."
                : "Speaking with: \(name), not verified. Personal data such as calendars stays locked.")
        } else {
            lines.append("Speaking with: a guest. Personal data such as calendars and reminders is locked.")
        }
        if context.isPersonalUnlocked, let about = context.aboutMember, !about.isEmpty, let name = context.memberName {
            lines.append("About \(name), in their words: \(about)")
        }
        if context.isPersonalUnlocked, let name = context.memberName, !context.memberMemories.isEmpty {
            lines.append("What you remember about \(name):\n" + context.memberMemories.map { "- \($0)" }.joined(separator: "\n"))
        }
        return lines
    }

    /// The longest screen summary a prompt carries. A recipe's ingredients fit,
    /// and the small on-device model gets less.
    static func screenLimit(compact: Bool) -> Int {
        compact ? 300 : 1200
    }

    /// "On screen: The Recipes app. The recipe card for…", and what "this" means.
    private static func screenSection(_ screen: String, compact: Bool) -> String {
        let limit = screenLimit(compact: compact)
        let text = screen.count > limit ? String(screen.prefix(limit - 1)) + "…" : screen
        return """
            On screen: \(text)
            Words like this, these or here mean what is on screen, unless the conversation says otherwise.
            """
    }

    /// One line per room, for example "Kitchen: Kitchen Lights (light, On, 70%)".
    /// Compact mode lists names only and caps the total.
    static func homeLines(for accessories: [HomeAccessory], compact: Bool) -> [String] {
        let limit = compact ? 25 : 80
        let grouped = Dictionary(grouping: accessories.prefix(limit)) { $0.room ?? "Other" }
        return grouped.keys.sorted().map { room in
            let items = (grouped[room] ?? []).map { accessory in
                if compact { return accessory.name }
                let status = accessory.statusText
                return status.isEmpty ? "\(accessory.name) (\(accessory.kind.rawValue))" : "\(accessory.name) (\(accessory.kind.rawValue), \(status))"
            }
            return "\(room): \(items.joined(separator: "; "))"
        }
    }
}
