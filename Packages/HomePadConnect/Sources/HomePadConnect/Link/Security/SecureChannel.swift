import CryptoKit
import Foundation

/// Errors from the sealed channel.
public enum SecureChannelError: Error, Equatable {
    case replayedOrOutOfOrder
    case malformed
}

/// Authenticated encryption for one connection after the handshake.
/// ChaChaPoly with a per-direction key and a counter nonce: frames must arrive
/// in order exactly once, so replays and reordering are rejected.
public struct SecureChannel {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    public private(set) var sentCount: UInt64 = 0
    public private(set) var receivedCount: UInt64 = 0

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        let nonce = try Self.nonce(for: sentCount)
        sentCount += 1
        return try ChaChaPoly.seal(plaintext, using: sendKey, nonce: nonce).combined
    }

    public mutating func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 12 + 16 else { throw SecureChannelError.malformed }
        let box = try ChaChaPoly.SealedBox(combined: sealed)
        guard Data(box.nonce) == Data(try Self.nonce(for: receivedCount)) else {
            throw SecureChannelError.replayedOrOutOfOrder
        }
        let plaintext = try ChaChaPoly.open(box, using: receiveKey)
        receivedCount += 1
        return plaintext
    }

    private static func nonce(for counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        Swift.withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }
}
