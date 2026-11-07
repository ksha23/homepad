import Foundation
import HomePadCore

/// The kind of a peer-link message. A string-backed struct rather than an enum,
/// so a newer HomePad can add types and older ones decode and ignore them.
public struct PeerMessageType: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    // Handshake (sent in the clear, before the secure channel exists).
    public static let hello = PeerMessageType("hello")
    public static let auth = PeerMessageType("auth")
    public static let pairProof = PeerMessageType("pair.proof")
    public static let pairGrant = PeerMessageType("pair.grant")
    public static let reject = PeerMessageType("reject")

    // App traffic (always sealed).
    public static let ping = PeerMessageType("ping")
    public static let statusRequest = PeerMessageType("status.request")
    public static let status = PeerMessageType("status")
    public static let command = PeerMessageType("command")
    /// A HomePad's `CommandReply` to one command. `RemoteProtocol.music` and later.
    public static let commandReply = PeerMessageType("command.reply")
    /// A companion starts or stops watching a HomePad's music (`MediaSubscription`).
    public static let mediaSubscribe = PeerMessageType("media.subscribe")
    /// A HomePad's `RemoteMediaStatus`, pushed to companions that watch it.
    public static let mediaStatus = PeerMessageType("media.status")
    public static let share = PeerMessageType("share")
    public static let intercomClip = PeerMessageType("intercom.clip")
    public static let intercomText = PeerMessageType("intercom.text")
    public static let alert = PeerMessageType("alert")
    public static let boardSync = PeerMessageType("board.sync")

    // Personal device approval (`RemoteProtocol.personalDevices` and later).
    /// A phone or Mac asks to approve for a member, or to stop (`ApprovalLinkRequest`).
    public static let approvalLink = PeerMessageType("approval.link")
    /// A phone or Mac asks a HomePad what it holds for it.
    public static let approvalStateRequest = PeerMessageType("approval.state.request")
    /// A HomePad's `ApprovalLinkState` for the device it tells.
    public static let approvalState = PeerMessageType("approval.state")
    /// A HomePad asks a member's device to approve (`ApprovalRequest`).
    public static let approvalRequest = PeerMessageType("approval.request")
    /// The device's answer (`ApprovalResponse`).
    public static let approvalResponse = PeerMessageType("approval.response")
    /// A HomePad no longer waits for a request (`ApprovalClosed`).
    public static let approvalClosed = PeerMessageType("approval.closed")

    /// Types allowed before authentication. Everything else is dropped until the channel is sealed.
    public var isHandshake: Bool {
        [.hello, .auth, .pairProof, .pairGrant, .reject].contains(self)
    }
}

/// One message on the HomePad peer link: a small JSON body plus an optional
/// binary attachment (AAC audio for intercom, JPEG for shared photos).
///
/// Typed bodies are plain `Codable` structs:
///
///     let message = try PeerMessage(type: .share, sender: id, content: item, attachment: jpeg)
///     let item = try message.content(SharedItem.self)
public struct PeerMessage: Equatable, Sendable {
    /// Bumped when the meaning of existing fields changes. New optional fields do not need a bump.
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var type: PeerMessageType
    /// Device ID of the sender.
    public var sender: String
    public var sentAt: Date
    public var body: JSONValue
    public var attachment: Data?

    public init(
        type: PeerMessageType, sender: String, body: JSONValue = .object([:]), attachment: Data? = nil,
        id: UUID = UUID(), sentAt: Date = Date(), version: Int = PeerMessage.currentVersion
    ) {
        self.version = version
        self.id = id
        self.type = type
        self.sender = sender
        self.sentAt = sentAt
        self.body = body
        self.attachment = attachment
    }

    /// Builds a message whose body is an encoded `Codable` value.
    public init<Content: Encodable>(type: PeerMessageType, sender: String, content: Content, attachment: Data? = nil) throws {
        self.init(type: type, sender: sender, body: try PeerCoding.jsonValue(from: content), attachment: attachment)
    }

    /// Decodes the body as a typed value.
    public func content<Content: Decodable>(_ type: Content.Type) throws -> Content {
        try PeerCoding.decode(type, from: body)
    }
}

/// Shared JSON settings so every device encodes bodies the same way.
public enum PeerCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    public static func jsonValue<Value: Encodable>(from value: Value) throws -> JSONValue {
        try decoder().decode(JSONValue.self, from: encoder().encode(value))
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) throws -> Value {
        try decoder().decode(type, from: encoder().encode(json))
    }
}
