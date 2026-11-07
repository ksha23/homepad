import Foundation

/// A HomePad's answer to one `.command` message. Body of a `.commandReply`
/// message, matched to the command by the command message's ID.
///
/// HomePads that speak `RemoteProtocol.music` or later send one for every
/// command. Older HomePads send none, so a companion only waits for a reply
/// from a HomePad whose status says it speaks that version.
public struct CommandReply: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// The command ran. `message` may say what happened ("Playing Blue in Green").
        case done
        /// The command could not run. `message` says why.
        case failed
        /// This HomePad cannot read the command. It needs an update.
        case unsupported

        /// An outcome a newer HomePad added reads as `failed`, so its message still shows.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Outcome(rawValue: raw) ?? .failed
        }
    }

    /// The `PeerMessage.id` of the command this answers.
    public var commandID: UUID
    public var outcome: Outcome
    /// A short sentence for the person, or nil.
    public var message: String?

    public init(commandID: UUID, outcome: Outcome, message: String? = nil) {
        self.commandID = commandID
        self.outcome = outcome
        self.message = message
    }
}
