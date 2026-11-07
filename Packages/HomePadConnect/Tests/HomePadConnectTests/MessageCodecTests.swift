import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

@Suite struct MessageCodecTests {
    private struct Sample: Codable, Equatable {
        var text: String
        var count: Int
        var when: Date
    }

    @Test func roundTripsBodyAndBinaryAttachment() throws {
        let audio = Data((0..<5000).map { UInt8($0 % 251) })
        let sample = Sample(text: "Dinner is ready", count: 3, when: Date(timeIntervalSince1970: 1_800_000_000))
        let message = try PeerMessage(type: .intercomClip, sender: "device-a", content: sample, attachment: audio)

        let decoded = try MessageCodec.decode(MessageCodec.encode(message))

        #expect(decoded.type == .intercomClip)
        #expect(decoded.sender == "device-a")
        #expect(decoded.id == message.id)
        #expect(decoded.version == PeerMessage.currentVersion)
        #expect(decoded.attachment == audio)
        #expect(try decoded.content(Sample.self) == sample)
    }

    @Test func messageWithoutAttachmentDecodesNilPayload() throws {
        let message = PeerMessage(type: .ping, sender: "x")
        let decoded = try MessageCodec.decode(MessageCodec.encode(message))
        #expect(decoded.attachment == nil)
        #expect(decoded.body == .object([:]))
    }

    @Test func attachmentStaysOutsideTheJSONHeader() throws {
        let payload = Data(repeating: 0xAB, count: 1000)
        let encoded = try MessageCodec.encode(PeerMessage(type: .share, sender: "x", attachment: payload))
        // 11 fixed bytes + small JSON header + raw payload, no base64 inflation.
        #expect(encoded.count < 11 + 400 + payload.count)
        #expect(encoded.suffix(payload.count) == payload)
    }

    @Test func unknownMessageTypesStillDecode() throws {
        let future = PeerMessage(type: PeerMessageType("hologram.call"), sender: "x")
        let decoded = try MessageCodec.decode(MessageCodec.encode(future))
        #expect(decoded.type.rawValue == "hologram.call")
        #expect(!decoded.type.isHandshake)
    }

    @Test func rejectsBadMagicNewerEnvelopeAndTruncation() throws {
        var encoded = try MessageCodec.encode(PeerMessage(type: .ping, sender: "x"))
        #expect(throws: PeerCodecError.truncated) { try MessageCodec.decode(encoded.dropLast()) }

        var badMagic = encoded
        badMagic[0] = 0x00
        #expect(throws: PeerCodecError.badMagic) { try MessageCodec.decode(badMagic) }

        encoded[2] = 9
        #expect(throws: PeerCodecError.unsupportedEnvelope(9)) { try MessageCodec.decode(encoded) }
    }

    @Test func frameDecoderReassemblesSplitAndJoinedFrames() throws {
        let first = try MessageCodec.encode(PeerMessage(type: .ping, sender: "a"))
        let second = try MessageCodec.encode(PeerMessage(type: .status, sender: "b", attachment: Data(repeating: 1, count: 300)))
        let stream = FrameDecoder.frame(first) + FrameDecoder.frame(second)

        var decoder = FrameDecoder()
        var frames: [Data] = []
        // Deliver in awkward 7-byte chunks.
        var index = 0
        while index < stream.count {
            let end = min(index + 7, stream.count)
            frames += try decoder.append(stream.subdata(in: index..<end))
            index = end
        }
        #expect(frames == [first, second])
        #expect(decoder.pendingByteCount == 0)
        #expect(try MessageCodec.decode(frames[1]).sender == "b")
    }

    @Test func frameDecoderRefusesOversizedFrames() {
        var decoder = FrameDecoder()
        var header = Data()
        header.appendBigEndian(UInt32(FrameDecoder.maxFrameLength + 1))
        #expect(throws: PeerCodecError.frameTooLarge(FrameDecoder.maxFrameLength + 1)) {
            _ = try decoder.append(header)
        }
    }

    @Test func remoteCommandsRoundTripThroughMessages() throws {
        let commands: [RemoteCommand] = [
            .showFace(id: "faces.photos"), .openApp(id: "timers"), .goAmbient,
            .startTimer(seconds: 300, label: "Pasta"), .cancelTimer(id: UUID()),
            .ask(prompt: "What's the weather?"), .runScene(id: "demo:scene.night"),
        ]
        for command in commands {
            let message = try PeerMessage(type: .command, sender: "phone", content: command)
            let decoded = try MessageCodec.decode(MessageCodec.encode(message))
            #expect(try decoded.content(RemoteCommand.self) == command)
        }
    }
}
