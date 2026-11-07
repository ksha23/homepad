import Foundation

/// A decoded HomeKit setup URI (`X-HM://...`), shown so the eight-digit setup
/// code can be read out or typed into the Home app. HomePad does not pair it.
struct HomeKitSetupPayload: Equatable {
    /// The eight setup code digits without dashes.
    var setupCode: String
    var category: Int
    var setupID: String?

    /// Decodes nine Base36 characters followed by an optional four-character setup ID.
    init?(uri: String) {
        guard uri.uppercased().hasPrefix("X-HM://") else { return nil }
        let rest = String(uri.dropFirst(7)).uppercased()
        guard rest.count >= 9, let value = UInt64(rest.prefix(9), radix: 36) else { return nil }
        let code = Int(value & 0x7FF_FFFF)
        guard code > 0, code <= 99_999_999 else { return nil }
        setupCode = String(format: "%08d", code)
        category = Int((value >> 31) & 0xFF)
        setupID = rest.count >= 13 ? String(rest.dropFirst(9).prefix(4)) : nil
    }

    /// Formatted the way HomeKit labels print it: 123-45-678.
    var formattedCode: String {
        let digits = Array(setupCode)
        return "\(String(digits[0..<3]))-\(String(digits[3..<5]))-\(String(digits[5...]))"
    }

    /// The accessory category name from the HomeKit Accessory Protocol.
    var categoryName: String {
        Self.categoryNames[category] ?? "Accessory"
    }

    private static let categoryNames: [Int: String] = [
        1: "Accessory", 2: "Bridge", 3: "Fan", 4: "Garage Door Opener", 5: "Light", 6: "Door Lock",
        7: "Outlet", 8: "Switch", 9: "Thermostat", 10: "Sensor", 11: "Security System", 12: "Door",
        13: "Window", 14: "Window Covering", 15: "Programmable Switch", 16: "Range Extender",
        17: "Camera", 18: "Video Doorbell", 19: "Air Purifier", 20: "Heater", 21: "Air Conditioner",
        22: "Humidifier", 23: "Dehumidifier", 28: "Sprinkler", 29: "Faucet", 30: "Shower System",
        31: "Television", 32: "Remote",
    ]
}
