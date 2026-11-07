import Foundation
import HomePadCore

/// Finds the devices someone means: "Kyle's iPhone", "my iPad", "everyone's
/// phone", "the kitchen iPad". Works only on the devices the person may see.
enum FindMyDeviceMatcher {
    /// - Parameters:
    ///   - device: What was said about the device. Nil or "all" means every device.
    ///   - owner: Whose: a name, "me", or nil and "everyone" for anyone's.
    ///   - devices: The devices the person may see.
    ///   - me: The member recognized right now, for "me" and "my".
    static func matches(device: String?, owner: String?, in devices: [FindMyDevice], me: HouseholdMember?) -> [FindMyDevice] {
        var words = words(in: device ?? "")
        var candidates = devices
        // "my iPad" and "Kyle's iPhone" name the owner inside the device.
        if let first = words.first, ["my", "mine"].contains(first) {
            candidates = owned(by: me, in: candidates)
            words.removeFirst()
        } else if let first = words.first, first.hasSuffix("s"), words.count > 1,
                  let member = FindMyOwnerMatcher.member(named: String(first.dropLast()), in: members(of: devices)),
                  FindMyOwnerMatcher.normalized(member.name).hasPrefix(String(first.dropLast())) {
            candidates = owned(by: member, in: candidates)
            words.removeFirst()
        }
        if let owner = owner.map(FindMyOwnerMatcher.normalized), !everyone.contains(owner) {
            if ["me", "my", "mine", "myself", "i"].contains(owner) {
                candidates = owned(by: me, in: candidates)
            } else if let member = FindMyOwnerMatcher.member(named: owner, in: members(of: devices)) {
                candidates = owned(by: member, in: candidates)
            } else {
                let wanted = flat(owner)
                candidates = candidates.filter { flat($0.title).contains(wanted) }
            }
        }
        words.removeAll { filler.contains($0) }
        guard !words.isEmpty else { return candidates }
        let phrase = words.joined(separator: " ")
        let named = candidates.filter { flat($0.title).contains(phrase) }
        if !named.isEmpty { return named }
        let kindWords = words.filter { word in FindMyDeviceKind.allCases.contains { $0.spokenWords.contains(word) } }
        let otherWords = words.filter { !kindWords.contains($0) }
        let byKind = kindWords.isEmpty ? candidates : candidates.filter { device in
            kindWords.contains { device.kind.spokenWords.contains($0) }
        }
        // Every other word must be in the name, so "Kyle's iPhone" never falls back to Sam's iPhone.
        return byKind.filter { device in
            let title = flat(device.title)
            return otherWords.allSatisfy { title.contains($0) }
        }
    }

    private static let everyone: Set<String> = ["", "everyone", "everybody", "all", "anyone", "anybody", "the family", "family", "household"]
    private static let filler: Set<String> = ["the", "a", "an", "all", "every", "everyone", "everyones", "everybodys", "devices", "device", "of", "our"]

    /// Lowercased words without punctuation, with "Kyle's" turned into "kyles".
    static func words(in text: String) -> [String] {
        FindMyOwnerMatcher.normalized(text)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// "Kyle’s iPhone" as "kyles iphone", to compare with what was said.
    static func flat(_ text: String) -> String {
        words(in: text).joined(separator: " ")
    }

    private static func owned(by member: HouseholdMember?, in devices: [FindMyDevice]) -> [FindMyDevice] {
        guard let member else { return [] }
        return devices.filter { $0.owner?.id == member.id }
    }

    private static func members(of devices: [FindMyDevice]) -> [HouseholdMember] {
        var seen = Set<UUID>()
        return devices.compactMap(\.owner).filter { seen.insert($0.id).inserted }
    }
}
