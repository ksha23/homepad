import Foundation

/// A chat thread as the hub reports it.
public struct CommsConversation: Codable, Identifiable, Hashable, Sendable {
    /// The Messages chat GUID, such as `iMessage;-;+15555550100`.
    public var id: String
    public var title: String
    /// Phone numbers or emails of everyone but the account owner.
    public var participants: [String]
    public var isGroup: Bool
    public var service: CommsService
    public var lastMessagePreview: String
    public var lastMessageDate: Date
    public var unreadCount: Int

    public init(
        id: String, title: String, participants: [String], isGroup: Bool, service: CommsService,
        lastMessagePreview: String, lastMessageDate: Date, unreadCount: Int
    ) {
        self.id = id
        self.title = title
        self.participants = participants
        self.isGroup = isGroup
        self.service = service
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
    }
}

public enum CommsService: String, Codable, Sendable {
    case iMessage = "iMessage"
    case sms = "SMS"
    case unknown
}
