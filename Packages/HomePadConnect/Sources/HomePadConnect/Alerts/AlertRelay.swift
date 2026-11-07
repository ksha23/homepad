import Foundation
import HomePadCore

/// Body of an `.alert` message from a HomePad to its companions.
struct AlertBody: Codable, Equatable {
    var alert: RelayedAlert
    var title: String
    var message: String
    var fromName: String
}

/// On a HomePad: forwards smoke, carbon monoxide and doorbell events to the
/// household's iPhones and Macs, and optionally to a Home Assistant notify
/// service so phones hear about it even when HomePad is not running on them.
@MainActor
final class AlertRelay {
    /// The same alert is relayed at most once per this many seconds.
    static let cooldown: TimeInterval = 60
    /// Sound-classifier confidence needed before relaying.
    static let minimumConfidence = 0.6

    private let services: AppServices
    private let link: PeerLink
    private var lastSent: [RelayedAlert: Date] = [:]
    private let log = Log.make("AlertRelay")

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
    }

    func start() {
        Task { [weak self, events = services.events] in
            for await event in events.stream() {
                guard let self, let alert = Self.alert(for: event) else { continue }
                await self.relay(alert)
            }
        }
    }

    /// Which alert an event represents, if any.
    static func alert(for event: HomePadEvent) -> RelayedAlert? {
        switch event {
        case .doorbellRang: .doorbell
        case .soundDetected(let label, let confidence) where confidence >= minimumConfidence:
            RelayedAlert(soundLabel: label)
        default: nil
        }
    }

    private func relay(_ alert: RelayedAlert, now: Date = Date()) async {
        guard services.settings[ConnectSettings.relayedAlerts].contains(alert) else { return }
        if let last = lastSent[alert], now.timeIntervalSince(last) < Self.cooldown { return }
        lastSent[alert] = now
        let room = link.identity.name
        let body = AlertBody(alert: alert, title: alert.title, message: Self.message(for: alert, room: room), fromName: room)
        if let message = try? link.message(.alert, body) {
            let delivered = await link.broadcast(message) { $0.kind.isCompanion }
            log.info("Relayed \(alert.rawValue, privacy: .public) to \(delivered.count) companions")
        }
        await notifyHomeAssistant(body)
    }

    private func notifyHomeAssistant(_ body: AlertBody) async {
        let service = services.settings[ConnectSettings.alertNotifyService].trimmingCharacters(in: .whitespaces)
        let parts = service.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        do {
            try await services.smartHome.callService(domain: parts[0], service: parts[1],
                                                     data: ["title": .string(body.title), "message": .string(body.message)])
        } catch {
            log.error("Home Assistant notify failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func message(for alert: RelayedAlert, room: String) -> String {
        switch alert {
        case .smoke: "HomePad in the \(room) hears a smoke alarm."
        case .carbonMonoxide: "HomePad in the \(room) hears a carbon monoxide alarm."
        case .doorbell: "Someone is at the door."
        }
    }
}
