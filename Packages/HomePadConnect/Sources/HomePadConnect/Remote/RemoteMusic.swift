import Foundation
import HomePadCore
import Observation
import UIKit

/// On a companion: the music of each HomePad it watches, pushed by the HomePad
/// over the link (`media.status`), and the music commands to send back.
///
/// Screens call `watch` when they appear and `stopWatching` when they go
/// (`.watchesMusic(of:)` does both). While anything watches a HomePad, the
/// HomePad pushes every change, and the watch is renewed after a reconnect.
@MainActor
@Observable
public final class RemoteMusic {
    /// A cover the HomePad sent as an attachment, decoded once.
    public struct Cover {
        public let key: String
        public let image: UIImage
    }

    public private(set) var statuses: [String: RemoteMediaStatus] = [:]
    /// When each HomePad's status arrived. Progress moves on from there.
    public private(set) var receivedAt: [String: Date] = [:]
    public private(set) var covers: [String: Cover] = [:]

    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let remote: RemoteHomePads
    /// How many screens watch each HomePad.
    @ObservationIgnored private var watchCounts: [String: Int] = [:]

    init(link: PeerLink, remote: RemoteHomePads) {
        self.link = link
        self.remote = remote
    }

    func start() {
        link.on(.mediaStatus) { [weak self] message, peer in
            self?.receive(message, from: peer.id)
        }
        link.onConnect { [weak self] peer in
            guard let self, self.watchCounts[peer.id] != nil else { return }
            self.sendWatching(true, to: peer.id)
        }
    }

    // MARK: Reading

    public func status(of peerID: String) -> RemoteMediaStatus? { statuses[peerID] }

    /// The cover of what plays on `peerID`, when it came as an attachment.
    public func cover(of peerID: String) -> UIImage? {
        guard let key = statuses[peerID]?.track?.artworkKey, let cover = covers[peerID], cover.key == key else { return nil }
        return cover.image
    }

    // MARK: Watching

    /// Starts watching a HomePad's music. Balance every call with `stopWatching`.
    public func watch(_ peerID: String) {
        watchCounts[peerID, default: 0] += 1
        if watchCounts[peerID] == 1 { sendWatching(true, to: peerID) }
    }

    public func stopWatching(_ peerID: String) {
        guard let count = watchCounts[peerID] else { return }
        if count > 1 {
            watchCounts[peerID] = count - 1
        } else {
            watchCounts[peerID] = nil
            sendWatching(false, to: peerID)
        }
    }

    /// True while any screen watches `peerID`.
    func isWatching(_ peerID: String) -> Bool { watchCounts[peerID] != nil }

    private func sendWatching(_ isWatching: Bool, to peerID: String) {
        guard let message = try? link.message(.mediaSubscribe, MediaSubscription(isWatching: isWatching)) else { return }
        Task { try? await remote.transmit(message, peerID) }
    }

    // MARK: Commands

    /// Sends a music command to one HomePad and waits for its answer. Returns
    /// the HomePad's sentence about it, such as "Playing Blue in Green.".
    @discardableResult
    public func send(_ command: MediaCommand, to peerID: String) async throws -> String? {
        try await remote.perform(.media(command: command), on: peerID)
    }

    // MARK: Receiving

    /// Takes in one `media.status` message.
    func receive(_ message: PeerMessage, from peerID: String) {
        guard let status = try? message.content(RemoteMediaStatus.self) else { return }
        if let key = status.track?.artworkKey, let data = message.attachment, let image = UIImage(data: data) {
            covers[peerID] = Cover(key: key, image: image)
        }
        statuses[peerID] = status
        receivedAt[peerID] = Date()
    }
}
