import Foundation

/// Plain words for who sees a calendar and why, for Settings and the apps.
/// Pure, so tests can check every case.
public enum CalendarAudienceText {
    /// A short label for a menu: "Everyone", "Kyle", "Kyle and Sam" or "Hidden".
    public static func short(_ audience: CalendarAudience, names: [UUID: String]) -> String {
        switch audience {
        case .everyone: return "Everyone"
        case .hidden: return "Hidden"
        case .members(let ids):
            let known = ownerNames(ids, names: names)
            return known.isEmpty ? "Hidden" : known.formatted(.list(type: .and))
        }
    }

    /// One or two sentences: who sees the calendar and why.
    public static func explanation(for status: CalendarStatus, unassigned: UnassignedCalendarPolicy, names: [UUID: String]) -> String {
        switch status.audience {
        case .everyone:
            switch status.origin {
            case .assigned:
                return "Shows for everyone, guests included."
            case .suggested:
                return "Shows for everyone. Holiday and Family calendars are shared unless you choose otherwise."
            case .unassignedRule:
                return unassigned == .admins
                    ? "Shows for everyone, because nobody in People is an admin yet."
                    : "Shows for everyone, because Calendars Nobody Chose are shared."
            }
        case .hidden:
            return status.origin == .unassignedRule
                ? "Hidden, because Calendars Nobody Chose is set to Hidden."
                : "Hidden, because it was set to Hidden here."
        case .members(let ids):
            if ids.isEmpty { return "Hidden, because it was unchecked for everyone it belonged to." }
            let known = ownerNames(ids, names: names)
            if known.isEmpty { return "Hidden, because it belongs to someone no longer in People." }
            let base = "Shows only while \(known.formatted(.list(type: .or))) is recognized."
            return status.origin == .unassignedRule ? "\(base) Nobody chose who it belongs to, so it belongs to the admins." : base
        }
    }

    /// The note under the Calendar or Reminders app, or nil when nothing is hidden.
    /// Names appear only for a recognized admin, who can see them in Settings anyway.
    public static func hiddenNote(_ hidden: HiddenCalendars, kind: CalendarSource.Kind, showsNames: Bool) -> String? {
        var sentences: [String] = []
        let noun = kind == .events ? "calendar" : "list"
        let waiting = hidden.awaitingOwner.count
        if waiting == 1 {
            sentences.append("1 personal \(noun) is hidden until its owner is recognized.")
        } else if waiting > 1 {
            sentences.append("\(waiting) personal \(noun)s are hidden until their owners are recognized.")
        }
        let off = hidden.hiddenInSettings
        if showsNames, !off.isEmpty {
            let titles = off.map(\.title).formatted(.list(type: .and))
            sentences.append("\(titles) \(off.count == 1 ? "is" : "are") hidden in Settings, under Personal Info.")
        } else if off.count == 1 {
            sentences.append("1 \(noun) is hidden in Settings, under Personal Info.")
        } else if off.count > 1 {
            sentences.append("\(off.count) \(noun)s are hidden in Settings, under Personal Info.")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// Names of the owners HomePad still knows, sorted so labels stay stable.
    static func ownerNames(_ ids: Set<UUID>, names: [UUID: String]) -> [String] {
        ids.compactMap { names[$0] }.sorted()
    }
}
