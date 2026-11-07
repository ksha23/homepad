import Foundation
import HomePadCore
import HomePadShareKit

/// Routes `homepad://` URLs. The app target posts every opened URL as
/// `.custom(name: "openURL", payload: .string(url))`. On a HomePad the link acts
/// locally. On a companion it is forwarded to the household's HomePads.
@MainActor
final class DeepLinkHandler {
    private let services: AppServices
    private let link: PeerLink
    private let sharing: ShareCenter
    private let log = Log.make("DeepLinks")

    init(services: AppServices, link: PeerLink, sharing: ShareCenter) {
        self.services = services
        self.link = link
        self.sharing = sharing
    }

    func start() {
        Task { [weak self, events = services.events] in
            for await event in events.stream() {
                guard case .custom(let name, let payload) = event, name == ConnectEventName.openURL,
                      let text = payload.stringValue, let url = URL(string: text) else { continue }
                await self?.handle(url)
            }
        }
    }

    func handle(_ url: URL) async {
        guard let deepLink = DeepLink(url: url) else {
            log.info("Ignoring URL \(url.absoluteString, privacy: .public)")
            return
        }
        if deepLink == .outbox {
            await sharing.deliverOutbox()
            return
        }
        if link.identity.kind.isCompanion {
            await forward(deepLink)
            return
        }
        if case .timer(let seconds, let label) = deepLink {
            services.timers.start(duration: seconds, label: label)
        }
        Self.events(for: deepLink).forEach(services.events.post)
    }

    /// Shell events for a link handled on this device.
    nonisolated static func events(for link: DeepLink) -> [HomePadEvent] {
        switch link {
        case .recipe(let url):
            [.custom(name: ConnectEventName.importRecipeURL, payload: .string(url.absoluteString))]
        case .outbox, .timer:
            []
        default:
            link.command.flatMap(CommandExecutor.event(for:)).map { [$0] } ?? []
        }
    }

    private func forward(_ deepLink: DeepLink) async {
        if case .recipe(let url) = deepLink {
            await sharing.send(SharedItem(kind: .recipe, url: url, senderName: link.identity.name), image: nil, to: nil)
            return
        }
        guard let command = deepLink.command,
              let message = try? link.message(.command, command) else { return }
        await link.broadcast(message) { $0.kind == .homePad }
    }
}
