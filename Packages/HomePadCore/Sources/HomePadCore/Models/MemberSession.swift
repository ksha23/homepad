import Foundation

/// What the camera can say about the face at the iPad. The Presence module
/// reports it to `Household.noteCamera(_:now:)` whenever it changes.
public enum CameraView: Equatable, Sendable {
    /// The camera is not looking for faces. It is off or paused, face
    /// recognition is off, or nobody has set up their face. It says nothing,
    /// so touches decide alone.
    case notWatching
    /// The camera watches and sees nobody at all.
    case nobody
    /// Someone is there, but no face is in view. They turned away, look down
    /// at the iPad or stand beside it.
    case noFace
    /// A face is in view, the nearest one when there are several.
    ///
    /// `look` names one unbroken view of that face. Losing the face, a second
    /// face coming into view or the face tracker switching faces starts a new
    /// look, and recognition decides about each look from scratch.
    case face(look: UUID, identity: FaceIdentity)
}

/// What recognition has decided about the face of one look.
public enum FaceIdentity: Hashable, Sendable {
    /// Not decided yet. It never moves a session either way.
    case unsure
    /// Confidently this household member. They won the recognition votes.
    case member(UUID)
    /// Confidently nobody in the household. Several clean samples in a row
    /// were each far from every face that was set up.
    case stranger
}

/// Who is signed in to HomePad, as one small state machine with injected time.
///
/// `Household` owns one and feeds it every event: what the camera sees, touches,
/// a pick in the People menu, Face ID or a personal device, a member leaving the
/// household, and a tick once a second from the kiosk. Nothing else keeps a
/// timer for the session. The rules are written out in the Presence README,
/// under "Who is signed in".
///
/// In short:
/// - A session belongs to an owner, the person the camera should see. That is
///   the member for a recognized or verified session, and whoever made the
///   choice for a pick by hand or Guest.
/// - It ends `timeout` seconds after the owner was last detected. The owner is
///   detected while their face is in view, and by a touch while no face is.
/// - A confident verdict about a face that is not the owner's takes over at
///   once: another member signs in, a stranger drops the iPad to Guest. An
///   unsure face moves nothing and keeps nothing alive.
public struct MemberSession: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Nobody's profile. The guest Home Screen, personal content hidden.
        case guest
        /// A member picked by hand. Their Home Screen, personal content locked.
        case picked(UUID)
        /// A member the camera recognized. Personal content unlocked.
        case recognized(UUID)
        /// A member who passed Face ID or approved on their personal device.
        /// Personal content unlocked.
        case verified(UUID)

        /// Whose profile shows.
        public var memberID: UUID? {
            switch self {
            case .guest: nil
            case .picked(let id), .recognized(let id), .verified(let id): id
            }
        }

        public var unlocksPersonalContent: Bool {
            switch self {
            case .guest, .picked: false
            case .recognized, .verified: true
            }
        }
    }

    public enum Event: Equatable, Sendable {
        /// What the camera sees now.
        case camera(CameraView)
        /// A finger on the screen.
        case touch
        /// A member picked by hand in the People menu, or nil for Guest.
        case picked(UUID?)
        /// Face ID or a personal device confirmed this member.
        case verified(UUID)
        /// This member left the household.
        case removed(UUID)
        /// Time passed. The kiosk sends one every second.
        case tick
    }

    /// A choice made while no face is in view takes the next face that comes
    /// into view within this many seconds as the chooser's. After Face ID the
    /// camera starts again within a few seconds, and that face is the person
    /// who just passed it.
    public static let adoptWindow: TimeInterval = 10

    public private(set) var mode: Mode = .guest
    public private(set) var view: CameraView = .notWatching
    /// When the owner was last detected.
    public private(set) var lastSeen: Date = .distantPast
    /// Who the session belongs to, as recognition names people. Nil for a guest
    /// nobody chose, or for a chooser the camera has not named yet.
    public private(set) var owner: FaceIdentity?
    /// Seconds without the owner before the session ends.
    public var timeout: TimeInterval
    /// The face that made a choice by hand or passed Face ID. It counts as the
    /// owner whatever recognition later says about it, until the look ends.
    private var ownLook: UUID?
    /// While set, the next new look becomes `ownLook`.
    private var adoptsNextLookUntil: Date?

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    /// True while the owner's face is the one in view.
    public var isOwnerInView: Bool {
        guard case .face(let look, let identity) = view else { return false }
        if look == ownLook { return true }
        return identity != .unsure && identity == owner
    }

    /// True while the session belongs to someone, so the timeout applies. A
    /// Guest chosen by hand belongs to its chooser: their own face does not
    /// sign them back in until they leave for the timeout.
    public var hasOwner: Bool {
        mode != .guest || owner != nil || ownLook != nil || adoptsNextLookUntil != nil
    }

    public mutating func handle(_ event: Event, at now: Date) {
        // The owner was in view until now, whatever the event changes.
        noteSeen(at: now)
        switch event {
        case .camera(let newView):
            see(newView, at: now)
        case .touch:
            if touchCounts { lastSeen = now }
        case .picked(let id):
            pick(id, at: now)
        case .verified(let id):
            begin(.verified(id), owner: .member(id), at: now, adoptsFace: true)
        case .removed(let id):
            if mode.memberID == id || owner == .member(id) { end() }
        case .tick:
            if hasOwner, now.timeIntervalSince(lastSeen) > timeout { end() }
        }
        noteSeen(at: now)
    }

    // MARK: Rules

    /// A touch keeps the session only when the camera cannot contradict it: no
    /// face is in view, the camera is not watching, or the face in view is the
    /// owner's. With any other face in view it counts for nothing.
    private var touchCounts: Bool {
        switch view {
        case .notWatching, .nobody, .noFace: true
        case .face: isOwnerInView
        }
    }

    private mutating func noteSeen(at now: Date) {
        if hasOwner, isOwnerInView { lastSeen = now }
    }

    private mutating func see(_ newView: CameraView, at now: Date) {
        view = newView
        guard case .face(let look, let identity) = newView else { return }
        if look != ownLook, let until = adoptsNextLookUntil {
            adoptsNextLookUntil = nil
            if now <= until { ownLook = look }
        }
        if look == ownLook {
            // The face that chose or passed Face ID never moves the session.
            // Once recognition names it, that name is the owner's.
            if owner == nil, identity != .unsure { owner = identity }
            if case .picked(let id) = mode, identity == .member(id) {
                begin(.recognized(id), owner: identity, at: now, adoptsFace: false)
            }
            return
        }
        switch identity {
        case .unsure:
            return
        case .member(let id):
            // Another member, a member arriving on a Guest Home Screen, or the
            // member whose Home Screen was picked by hand. The owner coming
            // back into view changes nothing.
            if owner != identity || mode == .picked(id) {
                begin(.recognized(id), owner: identity, at: now, adoptsFace: false)
            }
        case .stranger:
            if owner != .stranger { end() }
        }
    }

    private mutating func pick(_ id: UUID?, at now: Date) {
        if let id, id == mode.memberID {
            // Already showing them. Picking them again keeps the session.
            lastSeen = now
            return
        }
        // The chooser is whoever the camera names in view right now.
        var chooser: FaceIdentity?
        if case .face(_, let identity) = view, identity != .unsure { chooser = identity }
        if let id, chooser == .member(id) {
            // Picking yourself while the camera knows you.
            begin(.recognized(id), owner: chooser, at: now, adoptsFace: false)
        } else {
            begin(id.map(Mode.picked) ?? .guest, owner: chooser, at: now, adoptsFace: true)
        }
    }

    private mutating func begin(_ newMode: Mode, owner newOwner: FaceIdentity?, at now: Date, adoptsFace: Bool) {
        mode = newMode
        owner = newOwner
        lastSeen = now
        ownLook = nil
        adoptsNextLookUntil = nil
        guard adoptsFace else { return }
        if case .face(let look, _) = view {
            ownLook = look
        } else {
            adoptsNextLookUntil = now.addingTimeInterval(Self.adoptWindow)
        }
    }

    /// Back to a guest nobody chose.
    private mutating func end() {
        mode = .guest
        owner = nil
        ownLook = nil
        adoptsNextLookUntil = nil
    }
}
