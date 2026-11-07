import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

/// Kokoro-82M on the GPU through MLX: turns a sentence into 24 kHz audio. An actor,
/// so the model and its arrays stay on one thread off the main actor.
actor KokoroEngine {
    static let sampleRate: Double = 24_000

    private var tts: KokoroTTS?
    private var voices: [String: MLXArray] = [:]

    /// Loads the weights and the bundled voices, then speaks one word silently so the
    /// GPU kernels are compiled before the first real answer.
    func load(modelURL: URL) throws {
        guard tts == nil else { return }
        // A small cache: the model holds its own weights, and an always-on display
        // should not keep hundreds of megabytes of spare buffers.
        Memory.cacheLimit = 64 << 20
        guard let voicesURL = Bundle.module.url(forResource: "KokoroVoices", withExtension: "npz"),
              let loaded = NpyzReader.read(fileFromPath: voicesURL), !loaded.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        voices = loaded
        let engine = KokoroTTS(modelPath: modelURL, g2p: .misaki)
        tts = engine
        _ = try? synthesize("Hello.", voice: NaturalVoice.heart.fileKey, speed: 1)
    }

    /// Audio samples for `text`, splitting it in two when it is too long for the model.
    func synthesize(_ text: String, voice key: String, speed: Float) throws -> [Float] {
        guard let tts, let voice = voices[key + ".npy"] ?? voices.values.first else {
            throw CocoaError(.featureUnsupported)
        }
        let language: Language = key.hasPrefix("b") ? .enGB : .enUS
        do {
            return try tts.generateAudio(voice: voice, language: language, text: text, speed: speed).0
        } catch KokoroTTS.KokoroTTSError.tooManyTokens {
            let (first, second) = Self.halves(of: text)
            guard !first.isEmpty, !second.isEmpty else { throw KokoroTTS.KokoroTTSError.tooManyTokens }
            return try synthesize(first, voice: key, speed: speed) + synthesize(second, voice: key, speed: speed)
        }
    }

    /// The text split at the space nearest its middle.
    static func halves(of text: String) -> (String, String) {
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        let split = text[middle...].firstIndex(of: " ") ?? text[..<middle].lastIndex(of: " ") ?? middle
        return (String(text[..<split]).trimmingCharacters(in: .whitespaces),
                String(text[split...]).trimmingCharacters(in: .whitespaces))
    }
}
