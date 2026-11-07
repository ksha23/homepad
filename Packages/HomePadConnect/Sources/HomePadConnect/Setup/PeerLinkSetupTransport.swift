import Foundation
import HomePadCore

/// Carries the household setup sync over the peer link, between HomePads only.
/// Companions take no part: they have no Home Screen or faces of their own.
@MainActor
final class PeerLinkSetupTransport: SetupTransport {
    private let link: PeerLink
    private let log = Log.make("HouseholdSetup")

    init(link: PeerLink) {
        self.link = link
    }

    var householdID: String? { link.household?.id }

    func send(_ message: SetupMessage, to peerID: String) {
        guard let outgoing = try? message.peerMessage(sender: link.identity.deviceID) else { return }
        Task { [link, log] in
            do {
                try await link.send(outgoing, to: peerID)
            } catch {
                log.info("Setup \(outgoing.type.rawValue, privacy: .public) not sent: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func broadcast(_ message: SetupMessage) {
        guard let outgoing = try? message.peerMessage(sender: link.identity.deviceID) else { return }
        Task { [link] in await link.broadcast(outgoing) { $0.kind == .homePad } }
    }

    /// Hands the link's setup messages, and each session another HomePad opens, to `sync`.
    func connect(_ sync: HouseholdSetupSync) {
        for type in [PeerMessageType.setupHello, .setupDocuments] {
            link.on(type) { [weak sync] message, peer in
                guard peer.kind == .homePad, let setup = SetupMessage(message) else { return }
                sync?.receive(setup, from: peer.id, name: peer.name)
            }
        }
        link.onConnect { [weak sync] peer in
            guard peer.kind == .homePad else { return }
            sync?.connected(to: peer.id)
        }
    }
}
