import Foundation

/// What a scanned QR code means. HomePad only displays these. It never joins
/// networks or pairs accessories by itself.
enum QRPayload: Equatable {
    case wifi(WiFiNetwork)
    case url(URL)
    case matter(MatterSetupPayload)
    case homeKit(HomeKitSetupPayload)
    case text(String)

    struct WiFiNetwork: Equatable {
        var ssid: String
        /// "WPA", "WEP", "SAE" or nil for an open network.
        var security: String?
        var password: String?
        var isHidden: Bool
    }

    /// Recognizes the payload formats, most specific first.
    static func parse(_ raw: String) -> QRPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("WIFI:"), let network = parseWiFi(text) { return .wifi(network) }
        if text.hasPrefix("MT:"), let matter = MatterSetupPayload(qrCode: text) { return .matter(matter) }
        if text.uppercased().hasPrefix("X-HM://"), let homeKit = HomeKitSetupPayload(uri: text) { return .homeKit(homeKit) }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return .url(url)
        }
        return .text(text)
    }

    /// Parses `WIFI:T:WPA;S:My Network;P:secret;H:false;;`. Backslash escapes `\;`, `\,`, `\:` and `\\`.
    static func parseWiFi(_ text: String) -> WiFiNetwork? {
        var fields: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var escaping = false
        for character in text.dropFirst(5) {
            if escaping {
                if readingKey { key.append(character) } else { value.append(character) }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if readingKey, character == ":" {
                readingKey = false
            } else if character == ";" {
                if !key.isEmpty { fields[key.uppercased()] = value }
                key = ""
                value = ""
                readingKey = true
            } else if readingKey {
                key.append(character)
            } else {
                value.append(character)
            }
        }
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let security = fields["T"].flatMap { $0.isEmpty || $0.lowercased() == "nopass" ? nil : $0.uppercased() }
        let password = fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        return WiFiNetwork(ssid: ssid, security: security, password: password, isHidden: fields["H"]?.lowercased() == "true")
    }
}
