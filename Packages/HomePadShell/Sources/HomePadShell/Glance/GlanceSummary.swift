import Foundation
import HomePadCore

/// What the glance says, in the header and in the Glance and Home Status
/// widgets: today's events and reminders, unread messages, what is on at
/// home and what needs attention there, running timers and the weather.
///
/// It is built from plain values (`make`), so it can be tested without the
/// services. `GlanceReader` feeds it from them. Calendar, reminders and
/// messages are personal: the reader passes them only while someone is
/// recognized, and a category with nothing to say is left out.
struct GlanceSummary: Equatable {
    var events: Events?
    var reminders: Reminders?
    /// Unread messages, from the Messages app's badge.
    var unreadMessages = 0
    /// What needs attention at home, in `AttentionKind` order.
    var attention: [Attention] = []
    /// What is on at home, by kind, in `HomeKind` order.
    var home: [HomeGroup] = []
    var timers: Timers?
    /// The weather now, for the larger widgets.
    var weather: Weather?

    /// Events left today: all-day ones and those not over yet, as Up Next counts them.
    struct Events: Equatable {
        var count: Int
        /// The timed event on now or next, else the first all-day one.
        var next: CalendarItem
    }

    /// Open reminders due today or already overdue.
    struct Reminders: Equatable {
        var count: Int
        var overdue: Int
        /// The most pressing one: the first overdue, else the first due today.
        var first: String
    }

    /// Running and paused timers.
    struct Timers: Equatable {
        var count: Int
        /// The one that ends soonest.
        var soonest: HomeTimer
    }

    struct Weather: Equatable {
        var temperature: Int
        var symbolName: String
        var condition: String
    }

    /// Accessories of one kind that are on, such as lights.
    struct HomeGroup: Equatable {
        var kind: HomeKind
        var names: [String]
        /// The rooms they are in, the room with the most first.
        var rooms: [String]
        var count: Int { names.count }
    }

    /// Accessories in one state that wants a look, such as unlocked locks.
    struct Attention: Equatable {
        var kind: AttentionKind
        var names: [String]
        var count: Int { names.count }
    }

    /// The kinds of accessory the glance counts while they are on.
    enum HomeKind: CaseIterable, Sendable {
        case lights, fans, plugs, media, climate, purifiers, vacuums
    }

    /// States the glance points out, most pressing first.
    enum AttentionKind: CaseIterable, Sendable {
        case smoke, leak, unlocked, garageOpen, doorOpen, windowOpen
    }

    /// True when there is nothing to say at all.
    var isEmpty: Bool { items(includingTimers: true).isEmpty }
}

// MARK: Building

extension GlanceSummary {
    /// Personal parts of the glance. Nil while nobody is recognized.
    struct Personal: Equatable {
        /// Today's events, as the calendar service lists them for the day.
        var events: [CalendarItem] = []
        /// Open reminders, with their due date as `start` (`distantFuture` when undated).
        var reminders: [CalendarItem] = []
        var unreadMessages = 0
    }

    static func make(personal: Personal?, accessories: [HomeAccessory], timers: [HomeTimer],
                     weather: WeatherSnapshot?, now: Date, calendar: Calendar = .current) -> GlanceSummary {
        var summary = GlanceSummary()
        if let personal {
            summary.events = events(personal.events, now: now, calendar: calendar)
            summary.reminders = reminders(personal.reminders, now: now, calendar: calendar)
            summary.unreadMessages = max(personal.unreadMessages, 0)
        }
        // Each device once: a group of lamps is counted by its lamps.
        let devices = accessories.withoutGroups.filter(\.state.isReachable)
        summary.attention = AttentionKind.allCases.compactMap { kind in
            let names = devices.filter { attention(of: $0) == kind }.map(\.name)
            return names.isEmpty ? nil : Attention(kind: kind, names: names)
        }
        summary.home = HomeKind.allCases.compactMap { kind in
            let on = devices.filter { homeKind(of: $0) == kind }
            return on.isEmpty ? nil : HomeGroup(kind: kind, names: on.map(\.name), rooms: rooms(of: on))
        }
        let active = TopPillsContent.ordered(timers, at: now)
        if let soonest = active.first {
            summary.timers = Timers(count: active.count, soonest: soonest)
        }
        if let weather {
            summary.weather = Weather(temperature: Int(weather.temperature.rounded()), symbolName: weather.symbolName,
                                      condition: weather.conditionText)
        }
        return summary
    }

    /// Events left today, like Up Next: all-day events and those that have not ended.
    static func events(_ items: [CalendarItem], now: Date, calendar: Calendar) -> Events? {
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        let left = items.filter { item in
            !item.isReminder && item.start < today.end && item.end > today.start && (item.isAllDay || item.end > now)
        }
        let timed = left.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        guard let next = timed.first ?? left.first(where: \.isAllDay) else { return nil }
        return Events(count: left.count, next: next)
    }

    /// Open reminders due today or overdue, like the Today list in Reminders.
    static func reminders(_ items: [CalendarItem], now: Date, calendar: Calendar) -> Reminders? {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        let open = items.filter { !$0.isCompleted && $0.start < endOfToday }.sorted { $0.start < $1.start }
        guard !open.isEmpty else { return nil }
        // A reminder with a time is late once that time passes, one with only a day once the day ends.
        let overdue = open.filter { $0.isAllDay ? $0.start < startOfToday : $0.start < now }
        let first = overdue.first ?? open[0]
        return Reminders(count: open.count, overdue: overdue.count, first: first.title)
    }

    /// The kind an accessory counts under while it is on, nil while it is off or not counted.
    static func homeKind(of accessory: HomeAccessory) -> HomeKind? {
        let state = accessory.state
        switch accessory.kind {
        case .light: return state.isOn == true ? .lights : nil
        case .fan: return state.isOn == true ? .fans : nil
        case .switchOutlet: return state.isOn == true ? .plugs : nil
        // A speaker or TV that is on but quiet is not worth a mention.
        case .mediaPlayer: return state.isPlaying == true ? .media : nil
        case .thermostat: return state.hvacMode.map { $0 != .off } == true ? .climate : nil
        case .airPurifier: return state.isOn == true ? .purifiers : nil
        case .vacuum: return state.isOn == true ? .vacuums : nil
        default: return nil
        }
    }

    /// What about an accessory wants a look, if anything.
    static func attention(of accessory: HomeAccessory) -> AttentionKind? {
        let state = accessory.state
        switch accessory.kind {
        case .lock:
            return state.lockState == .unlocked ? .unlocked : nil
        case .garageDoor:
            return isOpen(state) ? .garageOpen : nil
        case .sensor:
            // Home Assistant's device classes, which HomeKit's sensors are named after too.
            switch accessory.deviceClass {
            case "smoke", "carbon_monoxide", "gas": return state.isActive == true ? .smoke : nil
            case "moisture": return state.isActive == true ? .leak : nil
            case "window": return isOpen(state) ? .windowOpen : nil
            case "garage_door": return isOpen(state) ? .garageOpen : nil
            case "door", "opening": return isOpen(state) ? .doorOpen : nil
            default: return nil
            }
        default:
            return nil
        }
    }

    /// A door, window or garage is open. Contact sensors that report no door
    /// state (HomeKit's) are active while open.
    private static func isOpen(_ state: AccessoryState) -> Bool {
        if let door = state.doorState, door != .unknown { return door == .open || door == .opening }
        if let position = state.position { return position > 0.01 }
        return state.isActive == true
    }

    /// Rooms in order of how many of the accessories are in each, then by name.
    private static func rooms(of accessories: [HomeAccessory]) -> [String] {
        let counts = Dictionary(accessories.compactMap(\.room).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    /// When the summary next changes on its own, with nothing edited: when one
    /// of today's timed events or reminders ends or falls due, or at midnight.
    static func nextChange(personal: Personal, now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86_400)
        let eventEnds = personal.events.filter { !$0.isAllDay }.map(\.end)
        let reminderDues = personal.reminders.filter { !$0.isAllDay }.map(\.start)
        let soonest = (eventEnds + reminderDues).filter { $0 > now }.min()
        return min(soonest ?? midnight, midnight)
    }
}
