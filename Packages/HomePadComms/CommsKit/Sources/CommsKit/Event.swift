import Foundation

/// What the hub pushes over `GET /v1/events`. On the wire it is flat JSON with a
/// `type` field (`message` or `read`), so any client can read it.
public enum CommsEvent: Codable, Hashable, Sendable {
    case message(CommsMessage)
    /// Messages in this conversation were read somewhere (this Mac or another device).
    case read(conversationID: String, unreadCount: Int)

    private enum CodingKeys: String, CodingKey { case type, message, conversationID, unreadCount }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "message": self = .message(try container.decode(CommsMessage.self, forKey: .message))
        case "read": self = .read(conversationID: try container.decode(String.self, forKey: .conversationID), unreadCount: try container.decode(Int.self, forKey: .unreadCount))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown event type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let message):
            try container.encode("message", forKey: .type)
            try container.encode(message, forKey: .message)
        case .read(let id, let count):
            try container.encode("read", forKey: .type)
            try container.encode(id, forKey: .conversationID)
            try container.encode(count, forKey: .unreadCount)
        }
    }
}

/// Hub status from `GET /v1/status`.
public struct HubStatus: Codable, Sendable {
    public var version: String
    /// The Apple ID or phone number Messages is signed in with, when known.
    public var account: String?
    public var canReadMessages: Bool
    public var canSendMessages: Bool

    public init(version: String, account: String?, canReadMessages: Bool, canSendMessages: Bool) {
        self.version = version
        self.account = account
        self.canReadMessages = canReadMessages
        self.canSendMessages = canSendMessages
    }
}
