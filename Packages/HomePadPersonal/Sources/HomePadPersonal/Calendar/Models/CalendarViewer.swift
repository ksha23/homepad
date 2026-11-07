import Foundation

/// The person looking at the screen, as far as calendar privacy is concerned.
public struct CalendarViewer: Equatable, Hashable, Sendable {
    public var memberID: UUID?
    /// True only after recognition or Face ID, never from picking a name by hand.
    public var isUnlocked: Bool
    /// Household admins, used to resolve `UnassignedCalendarPolicy.admins`.
    public var adminIDs: Set<UUID>

    public init(memberID: UUID?, isUnlocked: Bool, adminIDs: Set<UUID> = []) {
        self.memberID = memberID
        self.isUnlocked = isUnlocked
        self.adminIDs = adminIDs
    }

    /// Nobody recognized. Sees shared calendars only.
    public static let guest = CalendarViewer(memberID: nil, isUnlocked: false)

    /// The member whose personal calendars may show right now, if any.
    public var unlockedMemberID: UUID? {
        isUnlocked ? memberID : nil
    }
}
