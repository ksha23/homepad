import Foundation

/// Length-prefixed framing for a TCP byte stream. Every frame on the wire is a
/// 4-byte big-endian length followed by that many bytes (a plain envelope during
/// the handshake, a sealed envelope afterwards).
///
/// Feed it whatever chunks the socket delivers and it returns whole frames.
public struct FrameDecoder {
    /// Large enough for a full-resolution shared photo, small enough to refuse garbage.
    public static let maxFrameLength = 16 * 1024 * 1024

    private var buffer = Data()

    public init() {}

    /// Wraps one frame's bytes with its length prefix.
    public static func frame(_ body: Data) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(body.count))
        data.append(body)
        return data
    }

    /// Appends received bytes and returns every frame that is now complete, in order.
    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = Int(UInt32(bigEndianBytes: buffer.prefix(4)))
            guard length <= Self.maxFrameLength else { throw PeerCodecError.frameTooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            frames.append(Data(buffer[start..<(start + length)]))
            buffer = Data(buffer[(start + length)...])
        }
        return frames
    }

    /// Bytes received that do not yet form a whole frame.
    public var pendingByteCount: Int { buffer.count }
}
