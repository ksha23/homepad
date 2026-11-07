import Foundation

public extension PeerMessageType {
    /// A HomePad's `SetupHello`: where it stands and the versions it holds.
    static let setupHello = PeerMessageType("setup.hello")
    /// Shared documents (`SetupDocuments`).
    static let setupDocuments = PeerMessageType("setup.documents")
}

/// What a HomePad says when a session with another HomePad opens. Both say
/// it, and each answers the other's with the documents it holds newer, so a
/// HomePad never has to ask for what it lacks.
struct SetupHello: Codable, Equatable, Sendable {
    /// Bumped when the meaning of these messages changes.
    static let currentVersion = 1

    var version = SetupHello.currentVersion
    /// The household this HomePad belongs to, so a hello from another household is ignored.
    var householdID: String
    var standing: SetupStanding
    /// The version of every document it holds, deletions included. Empty
    /// while it does not share the household's setup yet.
    var manifest: [String: SetupVersion]

    var versions: [SetupKey: SetupVersion] {
        Dictionary(manifest.compactMap { key, version in SetupKey(key).map { ($0, version) } },
                   uniquingKeysWith: { first, _ in first })
    }
}

/// Documents for another HomePad: changes as they happen, what it lacks after
/// its hello, or newer versions than it sent.
struct SetupDocuments: Codable, Equatable, Sendable {
    var documents: [SetupDocument]
    /// Every document the sender holds, as it sends to a HomePad that joins
    /// its setup. A joining HomePad starts from this set only.
    var isComplete = false
    /// The sender's standing, sent with a complete set, so the HomePad that
    /// joins knows the set comes from the setup that wins whatever arrived first.
    var standing: SetupStanding?
}

/// One message between two HomePads about their shared setup.
enum SetupMessage: Equatable, Sendable {
    case hello(SetupHello)
    case documents(SetupDocuments)

    var type: PeerMessageType {
        switch self {
        case .hello: .setupHello
        case .documents: .setupDocuments
        }
    }

    /// Reads a peer message of one of the setup types. Nil for any other, or a body that does not decode.
    init?(_ message: PeerMessage) {
        switch message.type {
        case .setupHello:
            guard let body = try? message.content(SetupHello.self) else { return nil }
            self = .hello(body)
        case .setupDocuments:
            guard let body = try? message.content(SetupDocuments.self) else { return nil }
            self = .documents(body)
        default:
            return nil
        }
    }

    /// A peer message from `sender` that carries this one.
    func peerMessage(sender: String) throws -> PeerMessage {
        switch self {
        case .hello(let body): try PeerMessage(type: type, sender: sender, content: body)
        case .documents(let body): try PeerMessage(type: type, sender: sender, content: body)
        }
    }
}
