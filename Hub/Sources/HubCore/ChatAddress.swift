import Foundation

/// What the hub needs to show one chat in Messages, read from chat.db (`ChatDatabase.address(ofChat:)`).
public struct ChatAddress: Equatable, Sendable {
    /// The chat GUID, such as `iMessage;-;+15555550100`. From macOS 26 it starts with `any;`
    /// whatever the service, so the service is read from `service` instead.
    public var guid: String
    public var isGroup: Bool
    /// chat.db's `service_name`: `iMessage`, `SMS` or `RCS`.
    public var service: String
    /// chat.db's `chat_identifier`. In a chat with one person, their number or email.
    public var identifier: String
    /// Messages' own ID for the conversation (chat.db's `group_id`), when the chat has one.
    public var groupID: String?

    public init(guid: String, isGroup: Bool, service: String, identifier: String, groupID: String?) {
        self.guid = guid
        self.isGroup = isGroup
        self.service = service
        self.identifier = identifier
        self.groupID = groupID
    }

    /// The URL that brings this conversation forward in Messages, or nil when no URL is known to
    /// open the right one. Opening the wrong chat would mark that one read instead.
    ///
    /// - One person over iMessage: `imessage://<number or email>`, as the hub always did.
    /// - One person over SMS or RCS: `messages://open?groupid=<group_id>`. It names this exact chat,
    ///   so Messages cannot pick an iMessage chat with the same number. Without a group ID, `sms:<number>`.
    /// - A group: `messages://open?groupid=<group_id>`. Without a group ID, nil. A URL made from the
    ///   participants (`addresses=`) can land in another group with the same people, or start a new one.
    ///
    /// `messages://open?groupid=` is the URL macOS itself uses to open a conversation, from notifications,
    /// Shortcuts and Siri suggestions. Apple does not document it. See docs/COMMS.md, "Read state".
    public var openURL: URL? {
        if isGroup { return groupID.flatMap(Self.groupURL) }
        let handle = identifier.isEmpty ? (guid.split(separator: ";").last.map(String.init) ?? "") : identifier
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: Self.handleCharacters), !encoded.isEmpty else { return nil }
        if Self.isIMessage(service) { return URL(string: "imessage://" + encoded) }
        return groupID.flatMap(Self.groupURL) ?? URL(string: "sms:" + encoded)
    }

    /// iMessage, or a chat that does not say (`any`, from the GUID of a macOS 26 chat, or empty).
    private static func isIMessage(_ service: String) -> Bool {
        ["imessage", "any", ""].contains(service.lowercased())
    }

    private static func groupURL(_ groupID: String) -> URL? {
        guard !groupID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "messages"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "groupid", value: groupID)]
        return components.url
    }

    /// Phone numbers and emails pass as they are. Anything else is percent-encoded.
    private static let handleCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+@.-_"))
}
