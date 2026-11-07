import Foundation
import HomePadCore

// Each person's own Apple Music (`RemoteProtocol.memberAppleMusic` and later).
// The phone starts, and sends its Music User Token only to a HomePad that
// proves who it is, always on one sealed session:
//
//   phone   music.share          the member, and a fresh nonce for the HomePad to sign
//   HomePad music.proof          the nonce signed with the HomePad's key, or music.state with why not
//   phone   music.token          the member's Music User Token, on the session the proof came on
//   HomePad music.state          whether that member's Apple Music is linked here now
//   phone   music.unlink         the person turned it off: the HomePad forgets the token
//   phone   music.state.request  what the HomePad holds for this phone
extension PeerMessageType {
    /// A phone asks a HomePad to prove itself before it shares a member's Apple Music (`MusicShareRequest`).
    public static let musicShare = PeerMessageType("music.share")
    /// The HomePad's signature over the phone's nonce (`MusicShareProof`).
    public static let musicProof = PeerMessageType("music.proof")
    /// The member's Music User Token (`MusicTokenHandoff`).
    public static let musicToken = PeerMessageType("music.token")
    /// What a HomePad holds for the phone it tells (`MusicLinkState`).
    public static let musicState = PeerMessageType("music.state")
    /// The phone stops sharing a member's Apple Music (`MusicUnlink`).
    public static let musicUnlink = PeerMessageType("music.unlink")
    /// A phone asks a HomePad for its `MusicLinkState`.
    public static let musicStateRequest = PeerMessageType("music.state.request")
}

/// Limits of sharing Apple Music.
enum AppleMusicLinkPolicy {
    /// How long a share request waits for the HomePad's proof, and how long
    /// that proof stays good for the token that follows it.
    static let proofLifetime: TimeInterval = 30
    /// The longest token a HomePad keeps. Music User Tokens are a few hundred characters.
    static let maxTokenLength = 4096
    /// The least time between two token sends the phone makes on its own,
    /// so a token the API keeps turning down is not sent over and over.
    static let automaticResendInterval: TimeInterval = 6 * 60 * 60
}

/// Body of `music.share`.
public struct MusicShareRequest: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The member this phone is linked to on that HomePad.
    public var memberID: UUID
    /// 32 random bytes, single use.
    public var nonce: Data

    public init(requestID: UUID = UUID(), memberID: UUID, nonce: Data = ApprovalRequest.randomNonce()) {
        self.requestID = requestID
        self.memberID = memberID
        self.nonce = nonce
    }
}

/// Body of `music.proof`.
public struct MusicShareProof: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// ECDSA P256 over `MusicShareProof.signedBytes`, raw representation.
    public var signature: Data

    public init(requestID: UUID, signature: Data) {
        self.requestID = requestID
        self.signature = signature
    }

    /// What the HomePad signs: the nonce, the request, who it is for, and
    /// both devices, so a proof opens one token handoff, for one member, to one HomePad.
    static func signedBytes(requestID: UUID, nonce: Data, memberID: UUID, homePadID: String, phoneID: String) -> Data {
        let fields = ["homepad.music.v1", requestID.uuidString, nonce.base64EncodedString(), memberID.uuidString, homePadID, phoneID]
        return Data(fields.joined(separator: "\n").utf8)
    }
}

/// Body of `music.token`. The token reads the person's Apple Music library,
/// so its descriptions leave it out and nothing logs it.
public struct MusicTokenHandoff: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var requestID: UUID
    public var memberID: UUID
    /// The Music User Token MusicKit made on the phone.
    public var userToken: String

    public init(requestID: UUID, memberID: UUID, userToken: String) {
        self.requestID = requestID
        self.memberID = memberID
        self.userToken = userToken
    }

    public var description: String { "MusicTokenHandoff(request: \(requestID), member: \(memberID), token: redacted)" }
    public var debugDescription: String { description }
}

/// Body of `music.state`: what a HomePad holds for the phone it tells.
public struct MusicLinkState: Codable, Equatable, Sendable {
    /// The member this phone is linked to on that HomePad, nil when none.
    public var memberID: UUID?
    /// That member's Apple Music is linked there, with a token.
    public var isLinked: Bool
    /// The HomePad has no working token for that member and would like a new one.
    public var needsToken: Bool
    /// The share this answers, when it answers one.
    public var requestID: UUID?
    /// Why a share did not go through, in words.
    public var message: String?

    public init(memberID: UUID? = nil, isLinked: Bool = false, needsToken: Bool = false,
                requestID: UUID? = nil, message: String? = nil) {
        self.memberID = memberID
        self.isLinked = isLinked
        self.needsToken = needsToken
        self.requestID = requestID
        self.message = message
    }
}

/// Body of `music.unlink`.
public struct MusicUnlink: Codable, Equatable, Sendable {
    public var memberID: UUID

    public init(memberID: UUID) {
        self.memberID = memberID
    }
}

/// Why a HomePad did not take a share, or a phone did not send its token.
enum MusicShareRefusal: String, Error, Sendable {
    /// The phone is not linked to that member on that HomePad.
    case notLinked
    /// The member is no longer in the HomePad's household.
    case notMember
    /// The proof or the token came too late, on another session, or twice.
    case expired
    /// The HomePad has no key, or its signature did not match the key the phone kept.
    case notVerified
    /// The token was empty or too long.
    case badToken
}
