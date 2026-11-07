import Foundation

/// A decoded Matter onboarding QR code (`MT:...`), shown so the setup code can
/// be read out or typed into the Home app. HomePad does not pair it.
struct MatterSetupPayload: Equatable {
    var version: Int
    var vendorID: Int
    var productID: Int
    /// 0 standard, 1 user action required, 2 custom.
    var commissioningFlow: Int
    /// Bit 0 SoftAP, bit 1 BLE, bit 2 on network, bit 3 Wi-Fi PAF, bit 4 NFC.
    var discoveryCapabilities: Int
    var discriminator: Int
    var passcode: Int

    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.")

    /// Decodes the Base38 payload. Concatenated codes (`*`) use the first one.
    init?(qrCode: String) {
        guard qrCode.hasPrefix("MT:") else { return nil }
        let encoded = qrCode.dropFirst(3).split(separator: "*").first.map(String.init) ?? ""
        guard let bytes = Self.base38Decode(encoded), bytes.count >= 11 else { return nil }
        var reader = BitReader(bytes: bytes)
        version = reader.read(3)
        vendorID = reader.read(16)
        productID = reader.read(16)
        commissioningFlow = reader.read(2)
        discoveryCapabilities = reader.read(8)
        discriminator = reader.read(12)
        passcode = reader.read(27)
        guard version == 0, passcode > 0, passcode < 100_000_000 else { return nil }
    }

    /// The 11-digit manual pairing code, formatted like Matter labels (1234-567-8901).
    var manualPairingCode: String {
        let code = Self.manualCode(discriminator: discriminator, passcode: passcode)
        let digits = Array(code)
        return "\(String(digits[0..<4]))-\(String(digits[4..<7]))-\(String(digits[7...]))"
    }

    var discoveryDescription: String {
        var methods: [String] = []
        if discoveryCapabilities & 0b10 != 0 { methods.append("Bluetooth") }
        if discoveryCapabilities & 0b100 != 0 { methods.append("On your network") }
        if discoveryCapabilities & 0b1 != 0 { methods.append("Wi-Fi access point") }
        return methods.isEmpty ? "Not specified" : methods.joined(separator: ", ")
    }

    /// The short manual code (no vendor or product IDs), with its Verhoeff check digit.
    static func manualCode(discriminator: Int, passcode: Int) -> String {
        let shortDiscriminator = (discriminator >> 8) & 0xF
        let chunk1 = shortDiscriminator >> 2
        let chunk2 = ((shortDiscriminator & 0x3) << 14) | (passcode & 0x3FFF)
        let chunk3 = passcode >> 14
        let body = "\(chunk1)" + String(format: "%05d", chunk2) + String(format: "%04d", chunk3)
        return body + String(Verhoeff.checkDigit(for: body))
    }

    static func base38Decode(_ text: String) -> [UInt8]? {
        let characters = Array(text)
        var bytes: [UInt8] = []
        var index = 0
        while index < characters.count {
            let chunkLength = min(5, characters.count - index)
            let byteCount: Int
            switch chunkLength {
            case 5: byteCount = 3
            case 4: byteCount = 2
            case 2: byteCount = 1
            default: return nil
            }
            var value = 0
            for offset in (0..<chunkLength).reversed() {
                guard let digit = alphabet.firstIndex(of: characters[index + offset]) else { return nil }
                value = value * 38 + digit
            }
            for _ in 0..<byteCount {
                bytes.append(UInt8(value & 0xFF))
                value >>= 8
            }
            index += chunkLength
        }
        return bytes
    }

    /// Reads little-endian bit fields, least significant bit first.
    private struct BitReader {
        let bytes: [UInt8]
        var offset = 0

        mutating func read(_ count: Int) -> Int {
            var value = 0
            for bit in 0..<count {
                let position = offset + bit
                let byte = Int(bytes[position / 8])
                value |= ((byte >> (position % 8)) & 1) << bit
            }
            offset += count
            return value
        }
    }
}

/// The Verhoeff check digit Matter uses for manual pairing codes.
enum Verhoeff {
    private static let multiplication: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
        [2, 3, 4, 0, 1, 7, 8, 9, 5, 6], [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
        [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
        [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
        [8, 7, 6, 5, 9, 3, 2, 1, 0, 4], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
    ]
    private static let permutation: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
        [5, 8, 0, 3, 7, 9, 6, 1, 4, 2], [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
        [9, 4, 5, 3, 1, 2, 7, 6, 8, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
        [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
    ]
    private static let inverse = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]

    static func checkDigit(for digits: String) -> Int {
        var check = 0
        for (index, character) in digits.reversed().enumerated() {
            let digit = character.wholeNumberValue ?? 0
            check = multiplication[check][permutation[(index + 1) % 8][digit]]
        }
        return inverse[check]
    }
}
