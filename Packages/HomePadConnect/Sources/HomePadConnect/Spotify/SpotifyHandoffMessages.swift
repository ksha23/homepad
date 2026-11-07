import Foundation
import HomePadCore

// Each person's own Spotify on a HomePad, signed in on their own iPhone.
// The phone asks and the HomePad answers. The hello, the challenge and the
// handoff travel on one sealed session:
//
//   phone   spotify.state.request  what the HomePad holds for this phone's member
//   HomePad spotify.state          that member's Spotify there (`SpotifyStateReply`)
//   phone   spotify.hello          a sign-in to hand over: member, nonce, agreement key
//   HomePad spotify.challenge      its own agreement key and nonce, signed with the
//                                  HomePad's key, or spotify.refused with the reason
//   phone   spotify.handoff        Spotify's code and verifier sealed to the agreed key,
//                                  signed with the phone's approval key
//   HomePad spotify.result         the member's Spotify there now, or why not
//   phone   spotify.signOut        forget this member's Spotify there
extension PeerMessageType {
    /// A phone asks what a HomePad holds for its member's Spotify.
    public static let spotifyStateRequest = PeerMessageType("spotify.state.request")
    /// A HomePad's `SpotifyStateReply`.
    public static let spotifyState = PeerMessageType("spotify.state")
    /// A phone has a Spotify sign-in to hand over (`SpotifyHello`).
    public static let spotifyHello = PeerMessageType("spotify.hello")
    /// The HomePad's signed agreement key (`SpotifyChallenge`).
    public static let spotifyChallenge = PeerMessageType("spotify.challenge")
    /// The HomePad will not take the sign-in, and why (`SpotifyRefused`).
    public static let spotifyRefused = PeerMessageType("spotify.refused")
    /// The sealed and signed sign-in (`SpotifyHandoff`).
    public static let spotifyHandoff = PeerMessageType("spotify.handoff")
    /// What became of it (`SpotifyResult`).
    public static let spotifyResult = PeerMessageType("spotify.result")
    /// A phone signs its member's Spotify out on the HomePad (`SpotifySignOut`).
    public static let spotifySignOut = PeerMessageType("spotify.signOut")
}

/// Limits of handing a Spotify sign-in to a HomePad.
enum SpotifyHandoffPolicy {
    /// How long a challenge waits for its handoff: Face ID on the phone, then one message.
    static let lifetime: TimeInterval = 60
    /// How long the phone waits for each answer.
    static let replyTimeout: TimeInterval = 15
}

/// Body of `spotify.state`.
public struct SpotifyStateReply: Codable, Equatable, Sendable {
    /// False when the phone is not linked to anyone on that HomePad.
    public var isLinked: Bool
    /// The member's Spotify there. Nil when the HomePad has no Spotify at all.
    public var account: SpotifyMemberAccount?

    public init(isLinked: Bool, account: SpotifyMemberAccount?) {
        self.isLinked = isLinked
        self.account = account
    }
}

/// Body of `spotify.hello`.
public struct SpotifyHello: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The member the phone is linked to on that HomePad.
    public var memberID: UUID
    /// 32 random bytes, single use.
    public var nonce: Data
    /// The phone's one-time X25519 public key, raw representation.
    public var agreementKey: Data

    public init(requestID: UUID = UUID(), memberID: UUID, nonce: Data = ApprovalRequest.randomNonce(), agreementKey: Data) {
        self.requestID = requestID
        self.memberID = memberID
        self.nonce = nonce
        self.agreementKey = agreementKey
    }
}

/// Body of `spotify.challenge`.
public struct SpotifyChallenge: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The HomePad's own 32 random bytes.
    public var nonce: Data
    /// The HomePad's one-time X25519 public key, raw representation.
    public var agreementKey: Data
    /// ECDSA P256 with the HomePad's key (`HomePadKey`) over `signedBytes`.
    public var signature: Data

    public init(requestID: UUID, nonce: Data, agreementKey: Data, signature: Data) {
        self.requestID = requestID
        self.nonce = nonce
        self.agreementKey = agreementKey
        self.signature = signature
    }

    /// What the HomePad signs: both agreement keys and nonces, the member and
    /// both devices. Only the HomePad the phone linked to can sign it, so the
    /// key the phone seals to is that HomePad's and nobody else's.
    static func signedBytes(hello: SpotifyHello, nonce: Data, agreementKey: Data, homePadID: String, phoneID: String) -> Data {
        let fields = ["homepad.spotify.challenge.v1", hello.requestID.uuidString, hello.memberID.uuidString,
                      hello.nonce.base64EncodedString(), hello.agreementKey.base64EncodedString(),
                      nonce.base64EncodedString(), agreementKey.base64EncodedString(), homePadID, phoneID]
        return Data(fields.joined(separator: "\n").utf8)
    }
}

/// Why a HomePad did not take a Spotify sign-in.
public enum SpotifyRefusal: String, Codable, Sendable, Error {
    /// The phone is not linked to that member on that HomePad.
    case notLinked
    /// Spotify is off on the HomePad, or has no client ID.
    case notSetUp
    /// A signature or the sealed sign-in did not check out, or the HomePad has no key.
    case notVerified
    /// The request ran out, was used, or never existed.
    case expired
}

/// Body of `spotify.refused`.
public struct SpotifyRefused: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var reason: SpotifyRefusal

    public init(requestID: UUID, reason: SpotifyRefusal) {
        self.requestID = requestID
        self.reason = reason
    }
}

/// Body of `spotify.handoff`.
public struct SpotifyHandoff: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// `SpotifySignInCode`, sealed with ChaChaPoly (`SpotifyHandoffSeal`).
    public var sealed: Data
    /// ECDSA P256 with the phone's approval key over `signedBytes`.
    public var signature: Data

    public init(requestID: UUID, sealed: Data, signature: Data) {
        self.requestID = requestID
        self.sealed = sealed
        self.signature = signature
    }

    /// What the phone signs: the exchange, both devices, the member and the
    /// sealed sign-in, so only the linked phone hands a sign-in to its own member.
    static func signedBytes(hello: SpotifyHello, challenge: SpotifyChallenge, sealed: Data, homePadID: String, phoneID: String) -> Data {
        let fields = ["homepad.spotify.handoff.v1", hello.requestID.uuidString, hello.memberID.uuidString,
                      hello.nonce.base64EncodedString(), challenge.nonce.base64EncodedString(),
                      homePadID, phoneID, sealed.base64EncodedString()]
        return Data(fields.joined(separator: "\n").utf8)
    }
}

/// What travels sealed: Spotify's one-time code and the PKCE verifier that
/// goes with it. The HomePad exchanges them for tokens itself, so the refresh
/// token is made on the HomePad and never exists on the phone.
struct SpotifySignInCode: Codable, Equatable, Sendable {
    var code: String
    var verifier: String
}

/// Body of `spotify.result`.
public struct SpotifyResult: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The member's Spotify on the HomePad now.
    public var account: SpotifyMemberAccount?
    /// Why it did not work, in words, nil when it did.
    public var error: String?

    public init(requestID: UUID, account: SpotifyMemberAccount?, error: String? = nil) {
        self.requestID = requestID
        self.account = account
        self.error = error
    }
}

/// Body of `spotify.signOut`.
public struct SpotifySignOut: Codable, Equatable, Sendable {
    public var memberID: UUID

    public init(memberID: UUID) {
        self.memberID = memberID
    }
}
