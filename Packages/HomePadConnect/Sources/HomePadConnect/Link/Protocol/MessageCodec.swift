import Foundation
import HomePadCore

/// Errors from encoding or decoding peer-link bytes.
public enum PeerCodecError: Error, Equatable {
    case badMagic
    case unsupportedEnvelope(UInt8)
    case truncated
    case malformedHeader
    case frameTooLarge(Int)
}

/// Turns a `PeerMessage` into bytes and back.
///
/// Envelope layout (all integers big-endian):
///
///     "HP"            2 bytes magic
///     envelope        1 byte, currently 1
///     headerLength    4 bytes
///     payloadLength   4 bytes
///     header          JSON: {"v","id","type","from","at","body"}
///     payload         raw attachment bytes (AAC audio, JPEG)
///
/// Binary attachments ride outside the JSON so audio is never base64-inflated.
public enum MessageCodec {
    public static let envelopeVersion: UInt8 = 1
    static let magic: [UInt8] = [0x48, 0x50]   // "HP"
    static let fixedHeaderSize = 11

    private struct Header: Codable {
        var v: Int
        var id: UUID
        var type: PeerMessageType
        var from: String
        var at: Date
        var body: JSONValue
    }

    public static func encode(_ message: PeerMessage) throws -> Data {
        let header = Header(v: message.version, id: message.id, type: message.type,
                            from: message.sender, at: message.sentAt, body: message.body)
        let headerData = try PeerCoding.encoder().encode(header)
        let payload = message.attachment ?? Data()
        var data = Data(magic)
        data.append(envelopeVersion)
        data.appendBigEndian(UInt32(headerData.count))
        data.appendBigEndian(UInt32(payload.count))
        data.append(headerData)
        data.append(payload)
        return data
    }

    public static func decode(_ data: Data) throws -> PeerMessage {
        let bytes = [UInt8](data)
        guard bytes.count >= fixedHeaderSize else { throw PeerCodecError.truncated }
        guard Array(bytes[0..<2]) == magic else { throw PeerCodecError.badMagic }
        guard bytes[2] == envelopeVersion else { throw PeerCodecError.unsupportedEnvelope(bytes[2]) }
        let headerLength = Int(UInt32(bigEndianBytes: bytes[3..<7]))
        let payloadLength = Int(UInt32(bigEndianBytes: bytes[7..<11]))
        guard bytes.count == fixedHeaderSize + headerLength + payloadLength else { throw PeerCodecError.truncated }
        let headerStart = fixedHeaderSize
        let payloadStart = headerStart + headerLength
        let headerData = Data(bytes[headerStart..<payloadStart])
        guard let header = try? PeerCoding.decoder().decode(Header.self, from: headerData) else {
            throw PeerCodecError.malformedHeader
        }
        let payload = payloadLength > 0 ? Data(bytes[payloadStart..<(payloadStart + payloadLength)]) : nil
        return PeerMessage(type: header.type, sender: header.from, body: header.body, attachment: payload,
                           id: header.id, sentAt: header.at, version: header.v)
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

extension UInt32 {
    init<C: Collection>(bigEndianBytes bytes: C) where C.Element == UInt8 {
        self = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
