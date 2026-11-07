import Foundation
import HomePadCore

/// Carries out a `RemoteCommand` on this HomePad, by posting the matching
/// shell event or calling the owning service.
@MainActor
struct CommandExecutor {
    let services: AppServices

    /// Runs the command. Returns a short sentence for the companion, if there is
    /// something to say, and throws `RemoteCommandError` or the service's error.
    @discardableResult
    func execute(_ command: RemoteCommand) async throws -> String? {
        if let event = Self.event(for: command) {
            services.events.post(event)
            return nil
        }
        switch command {
        case .startTimer(let seconds, let label):
            services.timers.start(duration: seconds, label: label)
        case .cancelTimer(let id):
            services.timers.cancel(id)
        case .runScene(let id):
            try await services.smartHome.activateScene(id)
        case .media(let media):
            return try await execute(media)
        case .showFace, .openApp, .goAmbient, .ask:
            break
        }
        return nil
    }

    /// The shell event for commands that are pure navigation, nil for the rest.
    nonisolated static func event(for command: RemoteCommand) -> HomePadEvent? {
        switch command {
        case .showFace(let id): .showFace(id: id)
        case .openApp(let id): .openApp(id: id)
        case .goAmbient: .goAmbient
        case .ask(let prompt): .invokeAssistant(prompt: prompt.isEmpty ? nil : prompt)
        case .startTimer, .cancelTimer, .runScene, .media: nil
        }
    }
}

/// Why a HomePad turned a remote command down. The message reaches the companion.
enum RemoteCommandError: LocalizedError, Equatable {
    case emptySearch
    case searchTooLong
    case badNumber
    case unknownSpeaker
    case cannotSeek

    var errorDescription: String? {
        switch self {
        case .emptySearch: "Type something to play."
        case .searchTooLong: "That search is too long."
        case .badNumber: "That value is out of range."
        case .unknownSpeaker: "That speaker is not available anymore."
        case .cannotSeek: "This music cannot jump to another spot."
        }
    }
}

extension DeepLink {
    /// The equivalent remote command, for links a companion forwards to HomePads.
    var command: RemoteCommand? {
        switch self {
        case .app(let id): .openApp(id: id)
        case .face(let id): .showFace(id: id)
        case .ask(let prompt): .ask(prompt: prompt ?? "")
        case .timer(let seconds, let label): .startTimer(seconds: seconds, label: label)
        case .recipe, .outbox: nil
        }
    }
}
