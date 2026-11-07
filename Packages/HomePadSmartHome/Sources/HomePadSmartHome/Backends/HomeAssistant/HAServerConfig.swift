import Foundation
import HAKit
import HomePadCore

/// What `GET /api/config` says about the instance.
struct HAServerConfig: Equatable, Sendable {
    var locationName: String?
    var temperatureUnit: TemperatureUnit
    var version: String?

    init(json: JSONValue) {
        locationName = json["location_name"]?.stringValue
        version = json["version"]?.stringValue
        let unit = json["unit_system"]?["temperature"]?.stringValue ?? "°C"
        temperatureUnit = unit.contains("F") ? .fahrenheit : .celsius
    }
}
