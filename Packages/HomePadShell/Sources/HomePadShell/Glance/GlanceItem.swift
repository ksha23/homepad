import Foundation
import HomePadCore

/// One thing the glance shows, in the words and symbol every size draws
/// from: the symbol and count for small, the short phrase for medium, and
/// the detail for large. Tapping it opens `appID`.
struct GlanceItem: Identifiable, Equatable {
    enum ID: Hashable {
        case events, reminders, messages, timers
        case attention(GlanceSummary.AttentionKind)
        case home(GlanceSummary.HomeKind)
    }

    let id: ID
    let systemImage: String
    let count: Int
    /// "3 events", "5 lights on".
    let phrase: String
    /// The next event, the rooms that are lit, the door that is open. Nil when there is nothing more to say.
    let detail: String?
    /// What VoiceOver reads.
    let spokenLabel: String
    let appID: String
    /// True for what needs a look at home, which the widgets draw in orange.
    var isAttention: Bool {
        if case .attention = id { return true }
        return false
    }
}

/// The apps the glance opens.
enum GlanceAppID {
    static let calendar = "calendar"
    static let reminders = "reminders"
    static let messages = "messages"
    static let home = "home"
    static let timers = KnownAppID.timers
}

extension GlanceSummary {
    /// Everything to show, in reading order: the personal day first, then
    /// home, what needs a look before what is on. A row short of room drops
    /// items from the end.
    ///
    /// - Parameter includingTimers: False in the header, where the timer pill already sits.
    func items(includingTimers: Bool, now: Date = Date()) -> [GlanceItem] {
        var items: [GlanceItem] = []
        if let events { items.append(Self.item(events, now: now)) }
        if let reminders { items.append(Self.item(reminders)) }
        if unreadMessages > 0 {
            items.append(GlanceItem(id: .messages, systemImage: "message.fill", count: unreadMessages,
                                    phrase: "\(unreadMessages) unread", detail: nil,
                                    spokenLabel: Self.counted(unreadMessages, "unread message"), appID: GlanceAppID.messages))
        }
        items += homeItems()
        if includingTimers, let timers { items.append(Self.item(timers)) }
        return items
    }

    /// Only the home's part: what needs a look, then what is on.
    ///
    /// - Parameter namingAccessories: The detail of what is on names the
    ///   accessories (Home Status) rather than their rooms (the glance).
    func homeItems(namingAccessories: Bool = false) -> [GlanceItem] {
        attention.map(Self.item) + home.map { Self.item($0, namingAccessories: namingAccessories) }
    }

    private static func item(_ events: Events, now: Date) -> GlanceItem {
        let next = events.next
        let title = next.title
        let time = next.start.formatted(date: .omitted, time: .shortened)
        // The time comes first, so a long title is cut off rather than the time.
        let (detail, spoken): (String, String)
        if next.isAllDay {
            (detail, spoken) = (title, "\(title), all day")
        } else if next.start <= now {
            (detail, spoken) = ("Now: \(title)", "\(title), on now")
        } else {
            (detail, spoken) = ("\(time) \(title)", "next \(title) at \(time)")
        }
        let count = counted(events.count, "event")
        return GlanceItem(id: .events, systemImage: "calendar", count: events.count, phrase: count, detail: detail,
                          spokenLabel: "\(count) left today, \(spoken)", appID: GlanceAppID.calendar)
    }

    private static func item(_ reminders: Reminders) -> GlanceItem {
        let detail = reminders.overdue > 0 ? "\(reminders.overdue) overdue" : reminders.first
        return GlanceItem(id: .reminders, systemImage: "checklist", count: reminders.count,
                          phrase: counted(reminders.count, "reminder"), detail: detail,
                          spokenLabel: "\(counted(reminders.count, "reminder")) due today, \(detail)",
                          appID: GlanceAppID.reminders)
    }

    private static func item(_ timers: Timers) -> GlanceItem {
        let soonest = timers.soonest
        let detail = switch soonest.status {
        case .running: soonest.endDate.map { "\(soonest.label) ends \($0.formatted(date: .omitted, time: .shortened))" } ?? soonest.label
        default: "\(soonest.label) paused"
        }
        return GlanceItem(id: .timers, systemImage: "timer", count: timers.count, phrase: counted(timers.count, "timer"),
                          detail: detail, spokenLabel: "\(counted(timers.count, "timer")), \(detail)",
                          appID: GlanceAppID.timers)
    }

    private static func item(_ group: HomeGroup, namingAccessories: Bool) -> GlanceItem {
        let words = group.kind.words
        let phrase = "\(group.count) \(group.count == 1 ? words.one : words.many) \(words.state)"
        let places = namingAccessories || group.rooms.isEmpty ? group.names : group.rooms
        let detail = places.joined(separator: ", ")
        return GlanceItem(id: .home(group.kind), systemImage: group.kind.systemImage, count: group.count,
                          phrase: phrase, detail: detail, spokenLabel: "\(phrase), \(detail)", appID: GlanceAppID.home)
    }

    private static func item(_ attention: Attention) -> GlanceItem {
        let kind = attention.kind
        let phrase = "\(attention.count) \(attention.count == 1 ? kind.words.one : kind.words.many)"
        let detail = attention.names.joined(separator: ", ")
        return GlanceItem(id: .attention(kind), systemImage: kind.systemImage, count: attention.count, phrase: phrase,
                          detail: detail, spokenLabel: "\(detail), \(kind.words.spoken)", appID: GlanceAppID.home)
    }

    /// "1 reminder", "3 reminders".
    static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

extension GlanceSummary.HomeKind {
    var systemImage: String {
        switch self {
        case .lights: AccessoryKind.light.systemImage
        case .fans: AccessoryKind.fan.systemImage
        case .plugs: AccessoryKind.switchOutlet.systemImage
        case .media: AccessoryKind.mediaPlayer.systemImage
        case .climate: AccessoryKind.thermostat.systemImage
        case .purifiers: AccessoryKind.airPurifier.systemImage
        case .vacuums: AccessoryKind.vacuum.systemImage
        }
    }

    /// The accessory kind it stands for, for its tint.
    var accessoryKind: AccessoryKind {
        switch self {
        case .lights: .light
        case .fans: .fan
        case .plugs: .switchOutlet
        case .media: .mediaPlayer
        case .climate: .thermostat
        case .purifiers: .airPurifier
        case .vacuums: .vacuum
        }
    }

    /// "light" and "lights", then what they are doing.
    var words: (one: String, many: String, state: String) {
        switch self {
        case .lights: ("light", "lights", "on")
        case .fans: ("fan", "fans", "on")
        case .plugs: ("plug", "plugs", "on")
        case .media: ("speaker", "speakers", "playing")
        case .climate: ("thermostat", "thermostats", "on")
        case .purifiers: ("purifier", "purifiers", "on")
        case .vacuums: ("vacuum", "vacuums", "running")
        }
    }
}

extension GlanceSummary.AttentionKind {
    var systemImage: String {
        switch self {
        case .smoke: "smoke.fill"
        case .leak: "drop.triangle.fill"
        case .unlocked: "lock.open.fill"
        case .garageOpen: "door.garage.open"
        case .doorOpen: "door.left.hand.open"
        case .windowOpen: "window.vertical.open"
        }
    }

    /// "unlocked" for one and for several, and what VoiceOver says after the names.
    var words: (one: String, many: String, spoken: String) {
        switch self {
        case .smoke: ("smoke alarm", "smoke alarms", "detecting smoke")
        case .leak: ("leak", "leaks", "detecting a leak")
        case .unlocked: ("unlocked", "unlocked", "unlocked")
        case .garageOpen: ("garage open", "garages open", "open")
        case .doorOpen: ("door open", "doors open", "open")
        case .windowOpen: ("window open", "windows open", "open")
        }
    }
}
