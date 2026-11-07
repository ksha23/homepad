import Foundation
import Observation

/// A person in the household. Up to `Household.maxMembers` can be enrolled,
/// matching HomeView's six-person limit (HomePad allows the same by default).
public struct HouseholdMember: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Emoji or initials shown in the avatar bubble.
    public var avatar: String
    /// Hex color such as "#FF9500" for the avatar ring and accents.
    public var colorHex: String
    public var isAdmin: Bool
    /// Set by the Presence module once face enrollment succeeded.
    public var hasFaceEnrollment: Bool
    /// Per-person preferences that modules can read (assistant voice, default face, etc.).
    public var preferences: [String: JSONValue]

    /// The preference that holds the kind of face showing for this person,
    /// such as `faces.numerals`. The Faces module sets it from the person's
    /// current saved face, and the shell shows it.
    public static let facePreferenceKey = "faceID"

    public init(
        id: UUID = UUID(), name: String, avatar: String = "🙂", colorHex: String = "#0A84FF",
        isAdmin: Bool = false, hasFaceEnrollment: Bool = false, preferences: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.colorHex = colorHex
        self.isAdmin = isAdmin
        self.hasFaceEnrollment = hasFaceEnrollment
        self.preferences = preferences
    }
}

/// Who is using the device right now and whether their personal content may show.
///
/// The session itself is `MemberSession`, a pure state machine this class feeds:
/// the Presence module reports what the camera sees (`noteCamera(_:now:)`), the
/// shell's People switcher picks people (`select(_:now:)`), Face ID and personal
/// devices verify them (`recognize(_:now:)`), and the kiosk reports touches
/// (`noteActivity(now:)`) and ticks once a second (`expireIfNeeded(now:)`).
/// Every module reads `activeMember` and `isPersonalContentUnlocked`.
@MainActor
@Observable
public final class Household {
    public static let maxMembers = 6

    public private(set) var members: [HouseholdMember]
    /// Whose profile shows, nil for Guest.
    public private(set) var activeMemberID: HouseholdMember.ID?
    /// True only after the active member was recognized (face) or verified
    /// (Face ID / passcode), not merely picked in the People switcher.
    public private(set) var isPersonalContentUnlocked = false

    /// The session state machine. Not observed, since it notes the time every
    /// second while someone is in view. Observe `activeMemberID` and
    /// `isPersonalContentUnlocked` instead.
    @ObservationIgnored public private(set) var session = MemberSession()

    /// How long HomePad stays in a person's profile after it last detected them:
    /// the Presence & Privacy setting (`CoreSettings.signOutAfter`), unless a
    /// debug launch set its own.
    public var unlockWindow: TimeInterval {
        get { unlockWindowOverride ?? store[CoreSettings.signOutAfter] }
        set { unlockWindowOverride = newValue }
    }

    @ObservationIgnored private var unlockWindowOverride: TimeInterval?
    @ObservationIgnored private var memberIDChangeHandlers: [@MainActor (_ old: UUID, _ new: UUID) -> Void] = []
    private let store: SettingsStore
    private static let membersKey = SettingKey<[HouseholdMember]>("core.household.members", default: [])

    public init(store: SettingsStore) {
        self.store = store
        self.members = store[Self.membersKey]
    }

    public var activeMember: HouseholdMember? {
        members.first { $0.id == activeMemberID }
    }

    /// The active member once recognized or verified, nil while they are only
    /// picked in the People switcher. Personal content such as a person's
    /// assistant chats belongs to this member, so picking someone by hand
    /// never shows theirs.
    public var unlockedMember: HouseholdMember? {
        isPersonalContentUnlocked ? activeMember : nil
    }

    public var isGuest: Bool { activeMemberID == nil }

    // MARK: Membership

    @discardableResult
    public func add(_ member: HouseholdMember) -> Bool {
        guard members.count < Self.maxMembers else { return false }
        members.append(member)
        persist()
        return true
    }

    public func update(_ member: HouseholdMember) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index] = member
        persist()
    }

    public func remove(_ id: HouseholdMember.ID) {
        members.removeAll { $0.id == id }
        handle(.removed(id), at: Date())
        persist()
    }

    // MARK: Sharing with the household's other HomePads

    /// Shows a person as the household shares them (see `SharedMember`):
    /// adds someone new here, or updates everything but this iPad's own face
    /// enrollment and current face. It takes whoever the household has, even
    /// past `maxMembers` after two households' people were joined, so nobody
    /// is dropped. Adding someone by hand stays limited.
    public func applyShared(_ shared: SharedMember) {
        if let index = members.firstIndex(where: { $0.id == shared.id }) {
            let updated = shared.member(keeping: members[index])
            guard updated != members[index] else { return }
            members[index] = updated
        } else {
            members.append(shared.member(keeping: nil))
        }
        persist()
    }

    /// Calls `handler` when a person on this iPad takes the ID the household
    /// knows them by (`changeMemberID(from:to:)`). A module that keeps
    /// something per person on this iPad moves it from the old ID to the new
    /// one there, before the person changes, so nothing of theirs is lost or
    /// cleaned up as a removed person's.
    public func onMemberIDChange(_ handler: @escaping @MainActor (_ old: UUID, _ new: UUID) -> Void) {
        memberIDChangeHandlers.append(handler)
    }

    /// Gives a person the ID the household knows them by, when this iPad joins
    /// a household that already has them. The handlers move each module's data
    /// first, then the person takes the new ID in their place in the list. A
    /// session for them ends, since it belonged to the old ID.
    public func changeMemberID(from old: UUID, to new: UUID) {
        guard old != new, let index = members.firstIndex(where: { $0.id == old }),
              !members.contains(where: { $0.id == new }) else { return }
        memberIDChangeHandlers.forEach { $0(old, new) }
        members[index].id = new
        if session.mode.memberID == old { handle(.removed(old), at: Date()) }
        persist()
    }

    // MARK: Session

    /// Strong identification outside the camera: Face ID, a personal device, or
    /// a debug launch. Unlocks personal content. The camera's own recognition
    /// comes in through `noteCamera(_:now:)`.
    public func recognize(_ id: HouseholdMember.ID, now: Date = Date()) {
        guard members.contains(where: { $0.id == id }) else { return }
        handle(.verified(id), at: now)
    }

    /// Weak identification (picked by hand). Shows their layout but keeps
    /// personal content locked. Nil is Guest. Picking the person already shown
    /// keeps their session as it is.
    public func select(_ id: HouseholdMember.ID?, now: Date = Date()) {
        handle(.picked(id), at: now)
    }

    /// Guest, chosen by hand.
    public func signOut(now: Date = Date()) {
        handle(.picked(nil), at: now)
    }

    /// What the camera sees, from the Presence module, whenever it changes. A
    /// face named as someone who is not in the household counts as undecided.
    public func noteCamera(_ view: CameraView, now: Date = Date()) {
        var view = view
        if case .face(let look, .member(let id)) = view, !members.contains(where: { $0.id == id }) {
            view = .face(look: look, identity: .unsure)
        }
        handle(.camera(view), at: now)
    }

    /// Someone touched the screen. It keeps the session only while the camera
    /// sees no face, is not watching, or sees the session's own person, so a
    /// person verified with Face ID, or whose face the camera cannot see, is
    /// not signed out mid-use. It never unlocks anything by itself.
    public func noteActivity(now: Date = Date()) {
        handle(.touch, at: now)
    }

    /// Call once a second (the kiosk does). Ends the session `unlockWindow`
    /// seconds after its person was last detected.
    public func expireIfNeeded(now: Date = Date()) {
        handle(.tick, at: now)
    }

    private func handle(_ event: MemberSession.Event, at now: Date) {
        session.timeout = unlockWindow
        session.handle(event, at: now)
        let memberID = session.mode.memberID
        let unlocked = session.mode.unlocksPersonalContent
        // Written only on change, so views reading them do not redraw every second.
        if activeMemberID != memberID { activeMemberID = memberID }
        if isPersonalContentUnlocked != unlocked { isPersonalContentUnlocked = unlocked }
    }

    private func persist() {
        store[Self.membersKey] = members
    }
}
