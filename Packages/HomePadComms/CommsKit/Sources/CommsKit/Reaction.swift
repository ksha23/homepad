import Foundation

/// One tapback on a message, such as a heart from a friend.
public struct CommsReaction: Codable, Hashable, Sendable {
    /// `love`, `like`, `dislike`, `laugh`, `emphasize`, `question`, or `emoji` for a custom one.
    public var kind: String
    /// The emoji, only when `kind` is `emoji`.
    public var emoji: String?
    /// Phone number or email of who reacted, nil when the account owner did.
    public var sender: String?
    /// The reactor's name from Contacts, when they are in it.
    public var senderName: String?
    public var isFromMe: Bool

    public init(kind: String, emoji: String? = nil, sender: String? = nil, senderName: String? = nil, isFromMe: Bool) {
        self.kind = kind
        self.emoji = emoji
        self.sender = sender
        self.senderName = senderName
        self.isFromMe = isFromMe
    }
}
