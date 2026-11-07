import Foundation
import HAKit
import HomePadCore

/// Home Assistant's local push: `mobile_app/push_notification_channel` on the
/// WebSocket the backend already has, so `notify.mobile_app_<device>` reaches
/// this HomePad without a push service. HAKit opens it again after every
/// reconnect, as it does the other subscriptions.
///
/// Confirmations are off. With them, Home Assistant closes the channel when an
/// answer is late (the app was suspended), and the connection would not know.
extension HomeAssistantBackend {
    /// The request that opens the channel for a webhook.
    static func pushChannelRequest(webhookID: String) -> HARequest {
        HARequest(type: .webSocket("mobile_app/push_notification_channel"),
                  data: ["webhook_id": webhookID, "support_confirm": false])
    }

    /// Closes any channel and opens one for the current webhook on the current connection.
    func reopenPushChannel() {
        pushChannel?.cancel()
        pushChannel = nil
        if let connection { openPushChannel(on: connection) }
    }

    /// Opens the channel when this HomePad is a device. Called once per connection.
    func openPushChannel(on connection: HAConnection) {
        guard let webhookID = pushChannelWebhookID else { return }
        pushChannel = connection.subscribe(
            to: Self.pushChannelRequest(webhookID: webhookID),
            initiated: { [weak self] result in
                guard case .failure(let error) = result else { return }
                // "not_found" when Home Assistant no longer knows the webhook, so the device registers again.
                var unknown = false
                if case .external(let external) = error { unknown = external.code == "not_found" }
                MainActor.assumeIsolated {
                    // Home Assistant's reason never holds the webhook ID.
                    self?.log.error("The push channel was refused: \(error.localizedDescription, privacy: .public)")
                    self?.onPushChannelRefused?(unknown, error.localizedDescription)
                }
            },
            handler: { [weak self] _, data in
                MainActor.assumeIsolated { self?.onPushNotification?(JSONValue(haData: data)) }
            }
        )
    }
}
