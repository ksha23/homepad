import Foundation
import HomePadCore

/// Limits of personal device approval.
public enum ApprovalPolicy {
    /// How long a HomePad waits for an answer. A phone shows its prompt no longer.
    public static let requestLifetime: TimeInterval = 30
    /// How long a new link waits for someone to allow it on the HomePad.
    public static let linkLifetime: TimeInterval = 120
}

/// Someone in a HomePad's household, as a phone lists them when it links.
public struct ApprovalMember: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var avatar: String
    public var colorHex: String

    public init(id: UUID, name: String, avatar: String, colorHex: String) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.colorHex = colorHex
    }

    init(_ member: HouseholdMember) {
        self.init(id: member.id, name: member.name, avatar: member.avatar, colorHex: member.colorHex)
    }
}

/// Body of `approval.link`: a phone or Mac asks to approve unlocks for one
/// member on a HomePad. With no member it stops approving there.
public struct ApprovalLinkRequest: Codable, Equatable, Sendable {
    public var memberID: UUID?
    public var deviceName: String
    /// The device's P256 signing key (raw representation). Approvals must be
    /// signed with its private key, which never leaves the device.
    public var publicKey: Data
    /// The `RemoteProtocol` version the device speaks.
    public var remoteVersion: Int

    public init(memberID: UUID?, deviceName: String, publicKey: Data, remoteVersion: Int = RemoteProtocol.current) {
        self.memberID = memberID
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.remoteVersion = remoteVersion
    }
}

/// Body of `approval.state`: what a HomePad holds for the device it tells.
public struct ApprovalLinkState: Codable, Equatable, Sendable {
    /// The HomePad's household, to pick from when linking.
    public var members: [ApprovalMember]
    /// Who this device approves for on that HomePad.
    public var linkedMemberID: UUID?
    /// Who it asked to approve for, while that waits to be allowed on the HomePad.
    public var pendingMemberID: UUID?
    /// Why the last link did not go through, in words.
    public var message: String?
    /// The HomePad's own P256 public key (`HomePadKey`), raw representation.
    /// A linked phone keeps it and sends its photos only to a HomePad that
    /// signs with it. Missing from HomePads made before phone photos.
    public var homePadKey: Data?
    /// The IDs the HomePad knew the linked person by before it joined a
    /// household's setup. A device that kept something for one of them (Use My
    /// Apple Music) carries it over to `linkedMemberID`. Missing from older HomePads.
    public var formerMemberIDs: [UUID]?

    public init(members: [ApprovalMember] = [], linkedMemberID: UUID? = nil, pendingMemberID: UUID? = nil,
                message: String? = nil, homePadKey: Data? = nil, formerMemberIDs: [UUID]? = nil) {
        self.members = members
        self.linkedMemberID = linkedMemberID
        self.pendingMemberID = pendingMemberID
        self.message = message
        self.homePadKey = homePadKey
        self.formerMemberIDs = formerMemberIDs
    }

    public var linkedMember: ApprovalMember? { members.first { $0.id == linkedMemberID } }
    public var pendingMember: ApprovalMember? { members.first { $0.id == pendingMemberID } }
}

/// Body of `approval.request`: a HomePad asks a member's device to approve
/// opening an app. Single use: the HomePad accepts one answer to it, within
/// `lifetime` seconds.
public struct ApprovalRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 32 random bytes, signed with the answer, so an answer fits this request only.
    public var nonce: Data
    public var memberID: UUID
    public var homePadID: String
    public var homePadName: String
    public var appID: String
    public var appTitle: String
    /// Seconds the request stays open. Each side counts from when it sent or
    /// received it, so the two clocks never need to agree.
    public var lifetime: TimeInterval

    public init(id: UUID = UUID(), nonce: Data = ApprovalRequest.randomNonce(), memberID: UUID, homePadID: String,
                homePadName: String, appID: String, appTitle: String, lifetime: TimeInterval = ApprovalPolicy.requestLifetime) {
        self.id = id
        self.nonce = nonce
        self.memberID = memberID
        self.homePadID = homePadID
        self.homePadName = homePadName
        self.appID = appID
        self.appTitle = appTitle
        self.lifetime = lifetime
    }

    /// What an answer signs: the request's ID and nonce, and everything the
    /// phone shows about it, so a changed app or room breaks the signature.
    public func signedBytes(for decision: ApprovalDecision) -> Data {
        let fields = ["homepad.approval.v1", id.uuidString, nonce.base64EncodedString(), memberID.uuidString,
                      homePadID, homePadName, appID, appTitle, decision.rawValue]
        return Data(fields.joined(separator: "\n").utf8)
    }

    public static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// The person's answer on their device.
public enum ApprovalDecision: String, Codable, Sendable {
    case approve, deny
}

/// Body of `approval.response`. An approval carries a signature over the
/// request's `signedBytes(for: .approve)` made with the linked device's key.
public struct ApprovalResponse: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var decision: ApprovalDecision
    /// ECDSA P256 signature, raw representation. Required to approve.
    public var signature: Data?

    public init(requestID: UUID, decision: ApprovalDecision, signature: Data? = nil) {
        self.requestID = requestID
        self.decision = decision
        self.signature = signature
    }
}

/// Body of `approval.closed`: the HomePad no longer waits for this request,
/// because it was answered, withdrawn or ran out.
public struct ApprovalClosed: Codable, Equatable, Sendable {
    public var requestID: UUID

    public init(requestID: UUID) {
        self.requestID = requestID
    }
}
