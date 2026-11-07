import Foundation
import HomePadCore

/// The assistant's per-person choices, stored in `HouseholdMember.preferences`
/// so they travel with the member record.
public struct MemberAssistantPreferences: Equatable, Sendable {
    /// Keys inside `HouseholdMember.preferences`.
    public enum Key {
        public static let provider = "assistantProvider"
        public static let model = "assistantModel"
        public static let personality = "assistantPersonality"
        public static let aboutMe = "assistantAboutMe"
        public static let memories = "assistantMemories"
    }

    /// Longest "About me" text, so the system prompt stays small.
    public static let aboutMeLimit = 240
    /// Most memories saved for one member, so the prompt stays bounded.
    public static let memoryLimit = 50

    public var providerID: String?
    public var model: String?
    public var personality: Personality?
    public var aboutMe: String
    public var memories: [String]

    public init(member: HouseholdMember) {
        let prefs = member.preferences
        providerID = prefs[Key.provider]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        model = prefs[Key.model]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        personality = prefs[Key.personality]?.stringValue.flatMap(Personality.init(rawValue:))
        aboutMe = prefs[Key.aboutMe]?.stringValue ?? ""
        memories = prefs[Key.memories]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// Writes these choices into a copy of the member.
    public func applied(to member: HouseholdMember) -> HouseholdMember {
        var member = member
        member.preferences[Key.provider] = providerID.map(JSONValue.string)
        member.preferences[Key.model] = model.map(JSONValue.string)
        member.preferences[Key.personality] = personality.map { .string($0.rawValue) }
        let trimmed = String(aboutMe.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.aboutMeLimit))
        member.preferences[Key.aboutMe] = trimmed.isEmpty ? nil : .string(trimmed)
        let cappedMemories = Array(memories.prefix(Self.memoryLimit))
        member.preferences[Key.memories] = cappedMemories.isEmpty ? nil : .array(cappedMemories.map(JSONValue.string))
        return member
    }
}
