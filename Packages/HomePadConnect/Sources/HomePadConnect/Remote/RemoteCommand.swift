import Foundation
import HomePadCore

/// Something a companion (or another HomePad) asks a HomePad to do.
/// Travels as the body of a `.command` message.
///
/// A HomePad drops a command it cannot decode, and older HomePads do so without
/// a word. Before sending, a companion checks `minimumRemoteVersion` against the
/// HomePad's `HomePadStatus.remoteVersion`.
public enum RemoteCommand: Codable, Equatable, Sendable {
    case showFace(id: String)
    case openApp(id: String)
    case goAmbient
    case startTimer(seconds: Double, label: String)
    case cancelTimer(id: UUID)
    case ask(prompt: String)
    case runScene(id: String)
    /// Music control through the HomePad's `services.media`. Needs `RemoteProtocol.music`.
    case media(command: MediaCommand)

    /// The oldest `RemoteProtocol` version that understands this command.
    public var minimumRemoteVersion: Int {
        switch self {
        case .media: RemoteProtocol.music
        case .showFace, .openApp, .goAmbient, .startTimer, .cancelTimer, .ask, .runScene: RemoteProtocol.base
        }
    }
}
