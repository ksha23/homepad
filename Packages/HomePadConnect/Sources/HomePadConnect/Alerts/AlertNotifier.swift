import Foundation
import HomePadCore
import Observation
import UserNotifications

/// On an iPhone or Mac: turns relayed HomePad alerts into system notifications,
/// and keeps the latest one for an in-app banner.
@MainActor
@Observable
public final class AlertNotifier {
    public struct Received: Identifiable, Equatable {
        public let id = UUID()
        public let alert: RelayedAlert
        public let title: String
        public let message: String
        public let date: Date
    }

    public private(set) var latest: Received?
    public private(set) var isAuthorized = false

    @ObservationIgnored private let link: PeerLink

    init(link: PeerLink) {
        self.link = link
    }

    func start() {
        link.on(.alert) { [weak self] message, _ in
            guard let body = try? message.content(AlertBody.self) else { return }
            self?.show(body)
        }
        Task { isAuthorized = await Self.currentAuthorization() }
    }

    /// Asks for notification permission. Called when the person pairs or turns alerts on.
    public func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func dismiss() {
        latest = nil
    }

    private func show(_ body: AlertBody) {
        latest = Received(alert: body.alert, title: body.title, message: body.message, date: Date())
        let content = UNMutableNotificationContent()
        content.title = body.title
        content.body = body.message
        content.sound = body.alert == .doorbell ? .default : .defaultCritical
        content.interruptionLevel = body.alert == .doorbell ? .active : .timeSensitive
        content.threadIdentifier = "homepad.alerts"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func currentAuthorization() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }
}
