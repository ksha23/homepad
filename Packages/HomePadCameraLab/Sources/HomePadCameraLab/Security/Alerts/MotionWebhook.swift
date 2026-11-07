import Foundation
import HomePadCore

/// What HomePad sends to a Home Assistant webhook when motion is confirmed.
/// In Home Assistant, a "Webhook" automation trigger receives it and the fields
/// are available as `trigger.json.<field>`.
struct MotionAlertPayload: Codable, Equatable, Sendable {
    var event = "motion"
    var source: String
    var personDetected: Bool
    var changedFraction: Double
    var time: Date
    /// The token-protected snapshot URL, when the server is listening.
    var snapshotURL: String?

    enum CodingKeys: String, CodingKey {
        case event, source, time
        case personDetected = "person_detected"
        case changedFraction = "changed_fraction"
        case snapshotURL = "snapshot_url"
    }
}

/// Posts motion alerts to a user-entered Home Assistant webhook URL.
enum MotionWebhook {
    private static let log = Log.make("CameraLab.Webhook")

    /// Accepts only http and https URLs with a host.
    static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func encode(_ payload: MotionAlertPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Fire and forget, with a short timeout. Failures are logged, never shown as alarms.
    static func post(_ payload: MotionAlertPayload, to url: URL, session: URLSession = .shared) async {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encode(payload)
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                log.error("Webhook answered \(http.statusCode)")
            }
        } catch {
            log.error("Webhook failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
