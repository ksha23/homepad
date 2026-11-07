import Foundation

/// The random token that protects the camera stream (`?token=...`).
enum AccessToken {
    /// URL-safe letters and digits without look-alikes (no 0, O, 1, l, I),
    /// so the token survives being read aloud or typed from the screen.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
    /// Tokens shorter than this never match, so a blank or tiny token cannot open the stream.
    static let minimumLength = 16

    /// A new token from the system's cryptographically secure generator.
    /// 32 characters from a 57-letter alphabet is about 186 bits.
    static func generate(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// Compares in constant time for equal-length input, so response timing
    /// does not reveal how many leading characters were right.
    static func matches(_ provided: String?, expected: String) -> Bool {
        guard let provided, expected.count >= minimumLength else { return false }
        let given = Array(provided.utf8)
        let wanted = Array(expected.utf8)
        var difference: UInt8 = given.count == wanted.count ? 0 : 1
        for index in wanted.indices {
            difference |= wanted[index] ^ (index < given.count ? given[index] : 0)
        }
        return difference == 0
    }
}
