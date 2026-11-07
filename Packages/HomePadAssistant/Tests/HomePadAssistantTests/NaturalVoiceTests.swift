import CryptoKit
import Foundation
import Testing
@testable import HomePadAssistant

/// The Natural voice's pieces that do not need a GPU.
@Suite struct NaturalVoiceTests {
    @Test func voicesMapToTheirKeysInTheVoicesFile() {
        #expect(NaturalVoice.heart.fileKey == "af_heart")
        #expect(NaturalVoice.michael.fileKey == "am_michael")
        #expect(NaturalVoice.emma.fileKey == "bf_emma")
        #expect(NaturalVoice.george.fileKey == "bm_george")
        #expect(NaturalVoice.fable.displayName == "Fable (British)")
    }

    @Test func everyVoiceIsInTheBundledFile() throws {
        let url = try #require(Self.voicesInPackage())
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        for voice in NaturalVoice.allCases {
            #expect(text.contains(voice.fileKey + ".npy"), "\(voice.fileKey) is missing")
        }
    }

    @Test func longSentencesSplitNearTheMiddleAtASpace() {
        let (first, second) = KokoroEngine.halves(of: "The weather today is sunny with a light breeze from the west")
        #expect(!first.isEmpty && !second.isEmpty)
        #expect(first + " " + second == "The weather today is sunny with a light breeze from the west")
        #expect(abs(first.count - second.count) < 20)
    }

    @Test func checksumAndSizeCheck() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("natural-voice-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("model.bin")
        let bytes = Data((0..<(5 << 20)).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(try NaturalVoiceModel.sha256Hex(of: file) == expected)
        #expect(!NaturalVoiceModel.looksComplete(file), "a file of the wrong size is not the model")
    }

    /// The voices file in the package sources.
    private static func voicesInPackage() -> URL? {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HomePadAssistant/Resources/KokoroVoices.npz")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
