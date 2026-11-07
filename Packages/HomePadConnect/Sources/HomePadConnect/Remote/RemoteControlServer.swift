import Foundation
import HomePadCore

/// On a HomePad: carries out commands from companions, answers each with a
/// `CommandReply` and fresh status (faces, apps, timers, scenes), and pushes
/// the music to companions that watch it (`MediaStatusPublisher`).
///
/// Commands only arrive over sealed sessions with household members, the
/// same for every command. Values inside them are checked by `CommandExecutor`.
@MainActor
final class RemoteControlServer {
    private let services: AppServices
    private let registry: ModuleRegistry
    private let link: PeerLink
    let music: MediaStatusPublisher
    private let log = Log.make("Remote")

    init(services: AppServices, registry: ModuleRegistry, link: PeerLink) {
        self.services = services
        self.registry = registry
        self.link = link
        self.music = MediaStatusPublisher(services: services, link: link)
    }

    func start() {
        link.on(.statusRequest) { [weak self] _, peer in
            guard let self, let message = try? self.link.message(.status, self.status()) else { return }
            Task { try? await self.link.send(message, to: peer.id) }
        }
        link.on(.command) { [weak self] message, peer in
            guard let self else { return }
            Task {
                for reply in await self.handle(command: message, from: peer) {
                    try? await self.link.send(reply, to: peer.id)
                }
            }
        }
        music.start()
    }

    /// Runs one `.command` message and returns what to send back: its
    /// `CommandReply`, then fresh status. A command this HomePad cannot read
    /// (from a newer companion) gets `.unsupported`, so the companion can say
    /// "Update HomePad" instead of waiting.
    func handle(command message: PeerMessage, from peer: PeerDevice) async -> [PeerMessage] {
        let reply: CommandReply
        if let command = try? message.content(RemoteCommand.self) {
            do {
                let text = try await CommandExecutor(services: services).execute(command)
                reply = CommandReply(commandID: message.id, outcome: .done, message: text)
            } catch {
                log.error("Remote command failed: \(error.localizedDescription, privacy: .public)")
                reply = CommandReply(commandID: message.id, outcome: .failed, message: error.localizedDescription)
            }
            if case .media = command { music.publishSoon() }
        } else {
            log.info("Remote command from \(peer.name, privacy: .public) is newer than this HomePad")
            reply = CommandReply(commandID: message.id, outcome: .unsupported, message: Self.updateMessage(for: link.identity.name))
        }
        return [try? link.message(.commandReply, reply), try? link.message(.status, status())].compactMap { $0 }
    }

    func status() -> HomePadStatus {
        HomePadStatus(
            deviceID: link.identity.deviceID,
            name: link.identity.name,
            faces: registry.faces.map { .init(id: $0.id, title: $0.title, systemImage: $0.systemImage) },
            apps: registry.apps.filter { !$0.requiresRecognizedMember }.map { .init(id: $0.id, title: $0.title, systemImage: $0.systemImage) },
            timers: services.timers.timers,
            scenes: services.smartHome.scenes,
            nowPlaying: services.media.nowPlaying.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: ", ") },
            remoteVersion: RemoteProtocol.current
        )
    }

    /// What a companion shows when a HomePad is too old for what it asked.
    nonisolated static func updateMessage(for homePad: String) -> String {
        "Update HomePad on \(homePad) to use this from here."
    }
}
