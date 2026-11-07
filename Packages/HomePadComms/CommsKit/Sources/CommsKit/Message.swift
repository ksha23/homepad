import Foundation

/// One message in a conversation.
public struct CommsMessage: Codable, Identifiable, Hashable, Sendable {
    /// The Messages message GUID.
    public var id: String
    public var conversationID: String
    /// Phone number or email of the sender, nil when the account owner sent it.
    public var sender: String?
    /// The sender's name from Contacts, when they are in it.
    public var senderName: String?
    public var text: String
    public var date: Date
    public var isFromMe: Bool
    public var isRead: Bool
    public var attachments: [CommsAttachment]
    /// A rich link (web page, video, map) shown as one card instead of a bare URL.
    public var link: CommsLink?
    /// Tapbacks other people (or the owner) have put on this message.
    public var reactions: [CommsReaction]

    public init(
        id: String, conversationID: String, sender: String?, senderName: String? = nil, text: String, date: Date,
        isFromMe: Bool, isRead: Bool, attachments: [CommsAttachment] = [], link: CommsLink? = nil,
        reactions: [CommsReaction] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.sender = sender
        self.senderName = senderName
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
        self.isRead = isRead
        self.attachments = attachments
        self.link = link
        self.reactions = reactions
    }

    /// `reactions` is missing from old caches and old hubs, which decode as no reactions.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationID = try c.decode(String.self, forKey: .conversationID)
        sender = try c.decodeIfPresent(String.self, forKey: .sender)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        isFromMe = try c.decode(Bool.self, forKey: .isFromMe)
        isRead = try c.decode(Bool.self, forKey: .isRead)
        attachments = try c.decode([CommsAttachment].self, forKey: .attachments)
        link = try c.decodeIfPresent(CommsLink.self, forKey: .link)
        reactions = try c.decodeIfPresent([CommsReaction].self, forKey: .reactions) ?? []
    }
}

public struct CommsAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var mimeType: String
    public var name: String
    /// The picture's size in pixels, upright, for photos and PDFs (first page). Lets the iPad lay
    /// a photo out at its final size before it has loaded. Nil when unknown, as from older hubs.
    public var width: Int?
    public var height: Int?

    public init(id: String, mimeType: String, name: String, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.mimeType = mimeType
        self.name = name
        self.width = width
        self.height = height
    }
}

/// Body of `POST /v1/conversations/{id}/messages`.
public struct SendMessageRequest: Codable, Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

/// A link preview: where it goes, its title, and the attachment holding its picture.
public struct CommsLink: Codable, Hashable, Sendable {
    public var url: String
    public var title: String?
    public var imageAttachmentID: String?

    public init(url: String, title: String? = nil, imageAttachmentID: String? = nil) {
        self.url = url
        self.title = title
        self.imageAttachmentID = imageAttachmentID
    }
}
