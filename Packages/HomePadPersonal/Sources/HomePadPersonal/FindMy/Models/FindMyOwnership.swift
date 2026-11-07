import Foundation
import HomePadCore

/// Who a tracked device belongs to, as an admin set it in Settings, Personal
/// Info. Devices nobody chose for are matched automatically (see `FindMyOwnerMatcher`).
public enum FindMyOwnerChoice: Codable, Hashable, Sendable {
    case member(UUID)
    /// Belongs to nobody in the household, such as a shared iPad. Only admins see it.
    case nobody
    /// Never shown in HomePad.
    case hidden
}

/// A device's owner once choices and automatic matching are applied.
enum FindMyOwnership: Hashable, Sendable {
    case member(UUID)
    case nobody
    case hidden

    var memberID: UUID? {
        if case .member(let id) = self { return id }
        return nil
    }
}

/// Finds a device's owner among the household's members when nobody chose one:
/// first the owner Home Assistant names (a person that lists the tracker, or
/// iCloud's owner), then the name in front of the device's own name, as in
/// "Kyle's iPhone". First names are enough, so "Sam Rivera" finds Sam.
enum FindMyOwnerMatcher {
    static func ownership(of device: TrackedDevice, choice: FindMyOwnerChoice?, members: [HouseholdMember]) -> FindMyOwnership {
        switch choice {
        case .member(let id) where members.contains(where: { $0.id == id }): return .member(id)
        case .nobody: return .nobody
        case .hidden: return .hidden
        case .member, nil: return suggestedOwner(of: device, members: members).map { .member($0.id) } ?? .nobody
        }
    }

    static func suggestedOwner(of device: TrackedDevice, members: [HouseholdMember]) -> HouseholdMember? {
        for candidate in [device.ownerName, possessiveName(in: device.name)].compactMap({ $0 }) {
            if let member = member(named: candidate, in: members) { return member }
        }
        return nil
    }

    /// The member a name refers to: the whole name first, then the first names.
    static func member(named name: String, in members: [HouseholdMember]) -> HouseholdMember? {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return nil }
        if let exact = members.first(where: { normalized($0.name) == wanted }) { return exact }
        let first = firstWord(wanted)
        return members.first { firstWord(normalized($0.name)) == first }
    }

    /// "Kyle" from "Kyle's iPhone" or "Kyle’s iPad". Nil when the name has no owner in front.
    static func possessiveName(in deviceName: String) -> String? {
        for mark in ["'s ", "\u{2019}s "] {
            if let range = deviceName.range(of: mark, options: .caseInsensitive) {
                let owner = deviceName[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                return owner.isEmpty ? nil : owner
            }
        }
        return nil
    }

    /// Lowercased, without accents and extra spaces, so "Zoë" finds "zoe".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func firstWord(_ text: String) -> String {
        String(text.split(separator: " ").first ?? "")
    }
}
