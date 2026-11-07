import Foundation
import HomePadCore
import HomePadShareKit
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// "Send to HomePad". Companions send links, recipes, notes and photos.
/// HomePads receive them, hand recipes to Kitchen through events, and show
/// everything else in a glass card.
@MainActor
@Observable
public final class ShareCenter {
    /// Something that arrived, with its photo saved to disk.
    public struct Received: Identifiable, Equatable {
        public var item: SharedItem
        public var imageURL: URL?
        public var id: UUID { item.id }
    }

    /// The newest arrival, shown by the share overlay until dismissed.
    public private(set) var latest: Received?
    public private(set) var history: [Received] = []
    /// Items from the Share extension still waiting for a reachable HomePad.
    public private(set) var waitingInOutbox = 0

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let outbox = ShareOutbox.shared()
    private let log = Log.make("Share")

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
    }

    func start() {
        link.on(.share) { [weak self] message, peer in self?.receive(message, from: peer) }
        observeOutbox()
    }

    // MARK: Sending

    /// Sends to one HomePad, or all HomePads when `targetID` is nil. True when at least one got it.
    @discardableResult
    public func send(_ item: SharedItem, image: Data?, to targetID: String?) async -> Bool {
        guard let message = try? link.message(.share, item, attachment: image) else { return false }
        do {
            return try await !link.send(message, toHomePad: targetID).isEmpty
        } catch {
            log.error("Share failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Sends everything the Share extension queued.
    func deliverOutbox() async {
        guard let outbox else { return }
        publishTargets()
        for entry in outbox.pending() {
            let image = entry.imageURL.flatMap { try? Data(contentsOf: $0) }
            if await send(entry.item, image: image, to: entry.item.targetID) {
                outbox.remove(entry.item.id)
            }
        }
        waitingInOutbox = outbox.pending().count
    }

    /// Lets the Share extension offer the HomePads this device knows.
    public func publishTargets() {
        outbox?.saveTargets(link.homePads.map { ShareOutbox.Target(id: $0.id, name: $0.name) })
    }

    // MARK: Receiving

    public func dismissLatest() {
        latest = nil
    }

    private func receive(_ message: PeerMessage, from peer: PeerDevice) {
        guard var item = try? message.content(SharedItem.self) else { return }
        if item.senderName.isEmpty { item.senderName = peer.name }
        let imageURL = message.attachment.flatMap { save($0, id: item.id) }
        switch item.kind {
        case .recipe:
            if let url = item.url {
                services.events.post(.custom(name: ConnectEventName.importRecipeURL, payload: .string(url.absoluteString)))
            } else if let text = item.text {
                services.events.post(.custom(name: ConnectEventName.importRecipeText, payload: .string(text)))
            }
        case .photo:
            if let imageURL {
                services.events.post(.custom(name: ConnectEventName.photoReceived,
                                             payload: ["path": .string(imageURL.path), "from": .string(item.senderName)]))
            }
        case .link, .text:
            break
        }
        let received = Received(item: item, imageURL: imageURL)
        latest = received
        history.insert(received, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        services.events.post(.wake)
    }

    private func save(_ image: Data, id: UUID) -> URL? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SharedWithHomePad", isDirectory: true)
        let url = directory.appendingPathComponent("\(id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("Could not save shared photo: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Outbox wake-ups

    private func observeOutbox() {
        guard outbox != nil else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let center = Unmanaged<ShareCenter>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in await center.deliverOutbox() }
            },
            ShareOutbox.didEnqueueNotification as CFString, nil, .deliverImmediately
        )
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.deliverOutbox() }
        }
        #endif
        Task { await deliverOutbox() }
    }
}
