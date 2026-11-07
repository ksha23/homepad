import Foundation
import HomePadCore

/// Checks a URL and token before saving them: `GET /api/` must answer, then
/// `GET /api/config` says which home it is.
enum HomeAssistantConnectionTest {
    static func run(_ configuration: HomeAssistantConfiguration, session: URLSession = .shared) async throws -> String {
        let (_, apiResponse) = try await session.data(for: timed(configuration.request(path: "api/")))
        try check(apiResponse)
        let (configData, configResponse) = try await session.data(for: timed(configuration.request(path: "api/config")))
        try check(configResponse)
        let json = (try? JSONDecoder().decode(JSONValue.self, from: configData)) ?? .null
        let server = HAServerConfig(json: json)
        let name = server.locationName ?? "Home Assistant"
        return server.version.map { "Connected to \(name), version \($0)." } ?? "Connected to \(name)."
    }

    private static func timed(_ request: URLRequest) -> URLRequest {
        var request = request
        request.timeoutInterval = 10
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw SmartHomeError.backend("That address did not answer like Home Assistant.")
        }
        switch status {
        case 200..<300: return
        case 401, 403: throw SmartHomeError.backend("Home Assistant rejected the access token.")
        case 404: throw SmartHomeError.backend("That address is not a Home Assistant server.")
        default: throw SmartHomeError.backend("Home Assistant answered with status \(status).")
        }
    }
}
