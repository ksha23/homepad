import Foundation
import HomePadCore
import Speech

/// Text heard so far, since the engine started or was last reset.
struct TranscriptUpdate: Equatable, Sendable {
    var text: String
    var isFinal: Bool
}

/// On-device speech to text fed from `services.microphone`. Two
/// implementations exist: SpeechAnalyzer (preferred) and SFSpeechRecognizer.
@MainActor
protocol TranscriptionEngine: AnyObject {
    func start(onUpdate: @escaping @MainActor (TranscriptUpdate) -> Void) async throws
    func stop() async
    /// Forgets the text heard so far. Wake phrase listening calls this between phrases.
    func reset()
}

enum TranscriptionEngineFactory {
    /// SpeechAnalyzer when this iPad supports it, otherwise SFSpeechRecognizer forced on device.
    @MainActor
    static func make(microphone: MicrophoneHub, locale: Locale = .current) -> any TranscriptionEngine {
        if SpeechTranscriber.isAvailable {
            return AnalyzerTranscriptionEngine(microphone: microphone, locale: locale)
        }
        return LegacyTranscriptionEngine(microphone: microphone, locale: locale)
    }
}
