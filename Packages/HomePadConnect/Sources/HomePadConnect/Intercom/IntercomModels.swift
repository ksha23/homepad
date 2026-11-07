import Foundation

/// Where an intercom message goes: every HomePad, or one room.
public enum IntercomTarget: Codable, Hashable, Sendable {
    case everyone
    case device(id: String)
}

/// One intercom message, sent or received, for the history list.
public struct IntercomRecord: Identifiable, Equatable, Sendable {
    public enum Direction: String, Sendable { case sent, received }

    public var id: UUID
    public var direction: Direction
    /// The other side: "Kitchen", "Kyle's iPhone", or "Everywhere".
    public var peerName: String
    public var text: String?
    /// Local .m4a file for voice messages.
    public var audioURL: URL?
    public var duration: TimeInterval
    public var date: Date

    public var isVoice: Bool { audioURL != nil }
}

/// Body of an `.intercomClip` message. The AAC audio is the attachment.
struct IntercomClipBody: Codable, Equatable {
    var clipID: UUID
    var fromName: String
    var duration: TimeInterval
    /// File type of the attachment. Always "m4a" (AAC) today.
    var format: String
}

/// Body of an `.intercomText` message, spoken aloud on arrival.
struct IntercomTextBody: Codable, Equatable {
    var fromName: String
    var text: String
}
