import Foundation
import HomePadCore

/// How a HomePad that brings its own people joins a household that already
/// has a setup. The household's setup wins. Each of this iPad's people is
/// matched by name to the household's, takes the household's ID for them and
/// keeps this iPad's face data under it. People the household lacks join it.
struct SetupJoinPlan: Equatable, Sendable {
    /// One of this iPad's people the household already has.
    struct Match: Equatable, Sendable {
        /// Their ID on this iPad until now.
        var local: UUID
        /// The household's ID for them, which this iPad takes.
        var household: UUID
    }

    var matches: [Match]
    /// This iPad's people the household does not have. They keep their IDs and join it.
    var newcomers: [UUID]

    /// Matches `local`, this iPad's people in their order, to `household`, the
    /// household's. The same ID is a match first, as for a HomePad that shared
    /// this setup before. Then names match one to one, ignoring case, accents
    /// and spacing, in the order of each list.
    static func make(local: [HouseholdMember], household: [SharedMember]) -> SetupJoinPlan {
        var taken = Set<UUID>()
        var plan = SetupJoinPlan(matches: [], newcomers: [])
        var unmatched: [HouseholdMember] = []
        let householdIDs = Set(household.map(\.id))
        for member in local {
            if householdIDs.contains(member.id) {
                taken.insert(member.id)
            } else {
                unmatched.append(member)
            }
        }
        for member in unmatched {
            let name = normalizedName(member.name)
            if let match = household.first(where: { !taken.contains($0.id) && normalizedName($0.name) == name }) {
                taken.insert(match.id)
                plan.matches.append(Match(local: member.id, household: match.id))
            } else {
                plan.newcomers.append(member.id)
            }
        }
        return plan
    }

    /// A name as it is compared: trimmed, single spaces, no case or accents.
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Which of two HomePads keeps its setup when they first share one. A HomePad
/// that already shares the household's setup always wins. Between two that do
/// not yet, as when two HomePads that were set up apart start sharing, the one
/// that hosts the household wins, then the one installed first, then the
/// lower device ID, so both decide the same way.
struct SetupStanding: Codable, Hashable, Comparable, Sendable {
    /// It shares this household's setup already.
    var sharesSetup: Bool
    /// It showed a pairing code for the household, the first of which made the
    /// household's key. Other devices join the HomePad that shows the code.
    var hostsHousehold: Bool
    /// When HomePad was installed on it, in milliseconds since 1970.
    var installedAt: Int64
    var deviceID: String

    /// True when the left HomePad gives way to the right one.
    static func < (lhs: SetupStanding, rhs: SetupStanding) -> Bool {
        if lhs.sharesSetup != rhs.sharesSetup { return !lhs.sharesSetup }
        if lhs.hostsHousehold != rhs.hostsHousehold { return !lhs.hostsHousehold }
        if lhs.installedAt != rhs.installedAt { return lhs.installedAt > rhs.installedAt }
        return lhs.deviceID > rhs.deviceID
    }
}
