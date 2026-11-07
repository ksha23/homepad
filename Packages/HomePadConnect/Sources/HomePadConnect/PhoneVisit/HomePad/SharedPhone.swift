import Foundation
import HomePadCore

/// On a HomePad: a linked phone whose owner shares some of their data with it.
struct SharedPhone: Codable, Equatable, Sendable {
    /// The member the phone was linked to when it offered. An offer counts
    /// only while the phone is still linked to the same member.
    var memberID: UUID
    /// The tag the phone writes over Bluetooth, to wake it.
    var wakeTag: Data
    /// What the phone shares: photos, calendars, reminders.
    var kinds: Set<PhoneDataKind>

    init(memberID: UUID, wakeTag: Data, kinds: Set<PhoneDataKind>) {
        self.memberID = memberID
        self.wakeTag = wakeTag
        self.kinds = kinds
    }

    private enum CodingKeys: String, CodingKey { case memberID, wakeTag, kinds }

    /// Records saved before calendars have no kinds, and were for photos.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try container.decode(UUID.self, forKey: .memberID)
        wakeTag = try container.decode(Data.self, forKey: .wakeTag)
        let names = try container.decodeIfPresent([String].self, forKey: .kinds)
        kinds = names.map(PhoneDataKind.known) ?? [.photos]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memberID, forKey: .memberID)
        try container.encode(wakeTag, forKey: .wakeTag)
        try container.encode(PhoneDataKind.names(kinds), forKey: .kinds)
    }
}

/// Which phones share what, kept in this HomePad's settings: device IDs,
/// member IDs, random tags and kinds, nothing personal. The key kept its name
/// from when photos were the only kind.
enum SharedPhones {
    static let key = SettingKey<[String: SharedPhone]>("connect.photos.sharingDevices", default: [:])

    /// The records that still hold: the device is linked, to the same member,
    /// and that member is in the household.
    static func valid(_ records: [String: SharedPhone], linked: [LinkedDevice], members: Set<UUID>) -> [String: SharedPhone] {
        records.filter { id, record in
            members.contains(record.memberID) && linked.contains { $0.id == id && $0.memberID == record.memberID }
        }
    }

    /// The phone a visit of `member` goes to, the connected one first.
    static func phone(for member: UUID, in records: [String: SharedPhone], connected: Set<String>) -> String? {
        let ids = records.filter { $0.value.memberID == member }.keys.sorted()
        return ids.first { connected.contains($0) } ?? ids.first
    }

    /// The kinds each member shares through any of their phones.
    static func kindsByMember(_ records: [String: SharedPhone]) -> [UUID: Set<PhoneDataKind>] {
        records.values.reduce(into: [:]) { $0[$1.memberID, default: []].formUnion($1.kinds) }
    }
}
