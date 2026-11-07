import Foundation
import HomePadCore

/// How Home Assistant answered a webhook message.
enum MobileAppWebhookReply: Equatable, Sendable {
    /// Handled, with the JSON it answered (an empty object when it ignored the message).
    case handled(JSONValue)
    /// The registration was deleted in Home Assistant (status 410).
    case gone
    /// An empty answer: Home Assistant does not know the webhook, for example
    /// after the device was deleted and Home Assistant restarted.
    case unknownWebhook
}

/// The HTTP side of the `mobile_app` integration. The live one uses
/// `URLSession` on the configured address. Tests use a fake, so nothing
/// reaches a real Home Assistant.
@MainActor
protocol MobileAppTransport: AnyObject {
    /// `POST /api/mobile_app/registrations` with the long-lived token. Answers the body.
    func register(_ body: JSONValue, on configuration: HomeAssistantConfiguration) async throws -> JSONValue
    /// `POST /api/webhook/<id>`. The webhook ID is the credential, so no token goes with it.
    func send(_ message: JSONValue, webhookID: String, on configuration: HomeAssistantConfiguration) async throws -> MobileAppWebhookReply
    /// `DELETE /api/config/config_entries/entry/<id>`, which needs an admin's token.
    func deleteConfigEntry(_ entryID: String, on configuration: HomeAssistantConfiguration) async throws
}

/// `MobileAppTransport` over `URLSession`. Never logs a URL, since webhook URLs carry the webhook ID.
@MainActor
final class URLSessionMobileAppTransport: MobileAppTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func register(_ body: JSONValue, on configuration: HomeAssistantConfiguration) async throws -> JSONValue {
        var request = configuration.request(path: "api/mobile_app/registrations")
        request.httpMethod = "POST"
        request.httpBody = Data(body.jsonString().utf8)
        let (data, status) = try await perform(request)
        switch status {
        case 200..<300:
            return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        case 401, 403:
            throw SmartHomeError.backend("Home Assistant rejected the access token.")
        case 404:
            throw SmartHomeError.backend("Home Assistant's Mobile App integration is not loaded. It comes with default_config.")
        default:
            throw SmartHomeError.backend("Home Assistant answered the registration with status \(status).")
        }
    }

    func send(_ message: JSONValue, webhookID: String, on configuration: HomeAssistantConfiguration) async throws -> MobileAppWebhookReply {
        var request = URLRequest(url: Self.webhookURL(webhookID, base: configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(message.jsonString().utf8)
        let (data, status) = try await perform(request)
        switch status {
        case 410:
            return .gone
        case 200..<300:
            guard !data.isEmpty else { return .unknownWebhook }
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                throw SmartHomeError.backend("Home Assistant answered the webhook with something other than JSON.")
            }
            return .handled(json)
        default:
            throw SmartHomeError.backend("Home Assistant answered the webhook with status \(status).")
        }
    }

    func deleteConfigEntry(_ entryID: String, on configuration: HomeAssistantConfiguration) async throws {
        var request = configuration.request(path: "api/config/config_entries/entry/\(entryID)")
        request.httpMethod = "DELETE"
        let (_, status) = try await perform(request)
        switch status {
        case 200..<300: return
        case 401, 403: throw SmartHomeError.backend("Only a Home Assistant administrator's token can remove devices.")
        default: throw SmartHomeError.backend("Home Assistant answered the removal with status \(status).")
        }
    }

    /// `<base>/api/webhook/<id>`.
    static func webhookURL(_ webhookID: String, base: URL) -> URL {
        base.appending(path: "api/webhook").appending(path: webhookID)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        var request = request
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw SmartHomeError.backend("That address did not answer like Home Assistant.")
        }
        return (data, status)
    }
}
