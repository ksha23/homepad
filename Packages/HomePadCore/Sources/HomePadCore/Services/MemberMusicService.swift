import Foundation

/// Each household member's own Apple Music, linked from their own iPhone.
///
/// The iPad plays Apple Music only through its own Apple Account, and an app
/// cannot sign in to another one. What a member can bring is a Music User
/// Token, made by MusicKit on their own iPhone and handed to this HomePad over
/// the encrypted peer link. With it the HomePad reads that person's library,
/// recently played and recommendations from the Apple Music API. Playback
/// still goes through the iPad's own account.
///
/// The Connect module installs the real service and the Audio module reads it.
@MainActor
public protocol MemberMusicService: AnyObject {
    /// Members whose Apple Music is linked on this HomePad, by member ID. Nothing secret.
    var links: [UUID: MemberMusicLink] { get }

    /// The member's Music User Token, nil when there is none. It is a secret:
    /// never log it, show it or send it anywhere but the Apple Music API.
    func userToken(for member: UUID) -> String?

    /// The Apple Music API turned the member's token down. It is forgotten,
    /// and the member's phone is asked for a new one when it is next reachable.
    func tokenRejected(for member: UUID)
}

/// What a HomePad knows about one member's linked Apple Music.
public struct MemberMusicLink: Codable, Equatable, Sendable {
    /// The peer link ID of the phone that sent the token.
    public var deviceID: String
    /// Its name, such as "Kyle's iPhone".
    public var deviceName: String
    /// When the current token arrived. A new token changes it, so readers reload.
    public var linkedAt: Date
    /// The API turned the token down and the phone has not sent a new one yet.
    public var needsNewToken: Bool

    public init(deviceID: String, deviceName: String, linkedAt: Date, needsNewToken: Bool = false) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.linkedAt = linkedAt
        self.needsNewToken = needsNewToken
    }
}

/// Used until a module installs a real service: nobody's own Apple Music is linked.
@MainActor
public final class NoMemberMusic: MemberMusicService {
    public init() {}

    public var links: [UUID: MemberMusicLink] { [:] }
    public func userToken(for member: UUID) -> String? { nil }
    public func tokenRejected(for member: UUID) {}
}
