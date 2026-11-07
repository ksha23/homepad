import Foundation

/// The 6-digit code a HomePad shows while it accepts a new device.
public enum PairingCode {
    public static let length = 6
    /// How long a code stays valid after the window opens.
    public static let lifetime: TimeInterval = 180
    /// Wrong guesses allowed before the window closes.
    public static let maxAttempts = 5

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let value = Int.random(in: 0..<1_000_000, using: &generator)
        return String(format: "%06d", value)
    }

    /// Strips spaces and dashes. Returns nil unless exactly six digits remain.
    public static func normalize(_ input: String) -> String? {
        let digits = input.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == length, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    /// "123456" as "123 456" for display.
    public static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// An open pairing window on a host.
public struct PairingWindow: Equatable, Sendable {
    public var code: String
    public var expiresAt: Date
    public var failedAttempts = 0

    public init(code: String = PairingCode.generate(), expiresAt: Date = Date().addingTimeInterval(PairingCode.lifetime)) {
        self.code = code
        self.expiresAt = expiresAt
    }

    public func isOpen(at now: Date = Date()) -> Bool {
        now < expiresAt && failedAttempts < PairingCode.maxAttempts
    }
}
