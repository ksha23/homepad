import Foundation
import HomePadCore

// A phone visit: the HomePad opens a member's phone once, on one sealed
// session, for every kind of their data the phone shares with it (photos,
// calendars, reminders). The handshake kept its `photos.*` names from when
// photos were the only kind, so phones and HomePads from before calendars
// still open photos with newer ones:
//
//   HomePad visit hello      the member recognized here, and the kinds it wants
//   phone   visit challenge  a fresh nonce, or visit refused with the reason
//   HomePad visit open       the nonce signed with the HomePad's key
//   phone   visit opened     the kinds this session may ask for until it closes
//   ...                      each kind's own requests (photos.*, calendar.*, reminders.*)
//   HomePad visit close      nothing more for now
extension PeerMessageType {
    /// A HomePad asks a member's phone to open a visit (`PhoneVisitHello`).
    public static let visitHello = PeerMessageType("photos.hello")
    /// The phone's nonce for the HomePad to sign (`PhoneVisitChallenge`).
    public static let visitChallenge = PeerMessageType("photos.challenge")
    /// The phone will not open, and why (`PhoneVisitRefused`).
    public static let visitRefused = PeerMessageType("photos.refused")
    /// The HomePad's signature over the challenge (`PhoneVisitOpen`).
    public static let visitOpen = PeerMessageType("photos.open")
    /// The phone opened these kinds to this session (`PhoneVisitOpened`).
    public static let visitOpened = PeerMessageType("photos.opened")
    /// The HomePad needs nothing more for now (`PhoneVisitClose`).
    public static let visitClose = PeerMessageType("photos.close")
}

/// The kinds of a person's data a phone visit carries.
enum PhoneDataKind: String, Codable, CaseIterable, Sendable {
    case photos, calendars, reminders

    /// Kinds from the wire. Names this build does not know are skipped, so a
    /// newer device's kind never stops an older one from reading the rest.
    static func known(_ names: [String]) -> Set<PhoneDataKind> {
        Set(names.compactMap(PhoneDataKind.init(rawValue:)))
    }

    /// Names for the wire, in a fixed order.
    static func names(_ kinds: Set<PhoneDataKind>) -> [String] {
        allCases.filter(kinds.contains).map(\.rawValue)
    }
}

/// Limits of a visit, whatever it carries.
enum PhoneVisitPolicy {
    /// How long a challenge waits for the HomePad's signature.
    static let challengeLifetime: TimeInterval = 30
    /// How long an open session may ask without a new challenge.
    static let grantLifetime: TimeInterval = 10 * 60
}

/// Body of the visit hello.
public struct PhoneVisitHello: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The member recognized at the HomePad, who must be the phone's own.
    public var memberID: UUID
    /// The kinds the HomePad wants. Missing from HomePads that only knew
    /// photos, which is what it then means.
    public var kinds: [String]?

    public init(requestID: UUID = UUID(), memberID: UUID, kinds: [String]? = nil) {
        self.requestID = requestID
        self.memberID = memberID
        self.kinds = kinds
    }

    var requestedKinds: Set<PhoneDataKind> {
        kinds.map(PhoneDataKind.known) ?? [.photos]
    }
}

/// Body of the visit challenge.
public struct PhoneVisitChallenge: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// 32 random bytes, single use.
    public var nonce: Data

    public init(requestID: UUID, nonce: Data = ApprovalRequest.randomNonce()) {
        self.requestID = requestID
        self.nonce = nonce
    }
}

/// Why a phone did not open a visit.
public enum PhoneVisitRefusal: String, Codable, Sendable, Error {
    /// The phone is not linked to that member on that HomePad.
    case notLinked
    /// The person shares none of the kinds asked for with that HomePad.
    case notSharing
    /// HomePad on the phone has no access to the photo library.
    case noPhotoAccess
    /// HomePad on the phone has no full access to Calendar.
    case noCalendarAccess
    /// HomePad on the phone has no full access to Reminders.
    case noReminderAccess
    /// The phone has no key for the HomePad yet, or the signature did not match it.
    case notVerified
    /// The challenge ran out or was already used.
    case expired

    /// The refusal for a kind the person shares but HomePad cannot read.
    static func noAccess(to kind: PhoneDataKind) -> PhoneVisitRefusal {
        switch kind {
        case .photos: .noPhotoAccess
        case .calendars: .noCalendarAccess
        case .reminders: .noReminderAccess
        }
    }
}

/// Body of the visit refused.
public struct PhoneVisitRefused: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var reason: PhoneVisitRefusal

    public init(requestID: UUID, reason: PhoneVisitRefusal) {
        self.requestID = requestID
        self.reason = reason
    }
}

/// Body of the visit open.
public struct PhoneVisitOpen: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// ECDSA P256 over `PhoneVisitOpen.signedBytes`, raw representation.
    public var signature: Data

    public init(requestID: UUID, signature: Data) {
        self.requestID = requestID
        self.signature = signature
    }

    /// What the HomePad signs: the nonce, the request, who it is for, and
    /// both devices, so a signature opens one phone once, for one member, to
    /// one HomePad. The kinds are left out on purpose: the phone decides them
    /// from its own settings, and phones from before calendars check these bytes.
    static func signedBytes(requestID: UUID, nonce: Data, memberID: UUID, homePadID: String, phoneID: String) -> Data {
        let fields = ["homepad.photos.v1", requestID.uuidString, nonce.base64EncodedString(), memberID.uuidString, homePadID, phoneID]
        return Data(fields.joined(separator: "\n").utf8)
    }
}

/// Body of the visit opened.
public struct PhoneVisitOpened: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// What the session may ask for. Missing from phones that only knew photos.
    public var kinds: [String]?

    public init(requestID: UUID, kinds: [String]? = nil) {
        self.requestID = requestID
        self.kinds = kinds
    }

    var grantedKinds: Set<PhoneDataKind> {
        kinds.map(PhoneDataKind.known) ?? [.photos]
    }
}

/// Body of the visit close.
public struct PhoneVisitClose: Codable, Equatable, Sendable {
    public init() {}
}
