import Foundation

/// What of a person every HomePad in the household shares: their name, look,
/// role and preferences. Each HomePad keeps its own face enrollment, since
/// face data never leaves the iPad that made it, and its own current face for
/// them, which follows the faces it shares (`HouseholdMember.facePreferenceKey`).
public struct SharedMember: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var avatar: String
    public var colorHex: String
    public var isAdmin: Bool
    /// Every preference but the current face.
    public var preferences: [String: JSONValue]

    public init(id: UUID, name: String, avatar: String, colorHex: String, isAdmin: Bool,
                preferences: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.colorHex = colorHex
        self.isAdmin = isAdmin
        self.preferences = preferences
    }

    /// The shared part of a member as this iPad has them.
    public init(_ member: HouseholdMember) {
        var preferences = member.preferences
        preferences[HouseholdMember.facePreferenceKey] = nil
        self.init(id: member.id, name: member.name, avatar: member.avatar, colorHex: member.colorHex,
                  isAdmin: member.isAdmin, preferences: preferences)
    }

    /// The member to keep on this iPad: the shared part, plus this iPad's own
    /// enrollment and current face from `local`, the person as this iPad had
    /// them (nil for someone new here).
    public func member(keeping local: HouseholdMember?) -> HouseholdMember {
        var preferences = preferences
        preferences[HouseholdMember.facePreferenceKey] = local?.preferences[HouseholdMember.facePreferenceKey]
        return HouseholdMember(id: id, name: name, avatar: avatar, colorHex: colorHex, isAdmin: isAdmin,
                               hasFaceEnrollment: local?.hasFaceEnrollment ?? false, preferences: preferences)
    }
}
