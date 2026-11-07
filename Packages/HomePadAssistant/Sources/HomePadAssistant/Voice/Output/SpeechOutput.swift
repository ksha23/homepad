import AVFoundation
import Foundation

/// Something that reads text aloud. `speak` returns when the text finished or was stopped.
@MainActor
protocol SpeechOutput: AnyObject {
    func speak(_ text: String) async throws
    func stop()
    /// Starts making audio for text that will be spoken soon. Optional.
    func prepare(_ text: String)
}

extension SpeechOutput {
    func prepare(_ text: String) {}
}

/// Reads text with an installed system voice through AVSpeechSynthesizer.
@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    var voiceIdentifier = ""
    var rate: SpeakingRate = .normal

    override init() {
        super.init()
        synthesizer.delegate = self
        // The voice speaks in its own system audio session, the way Siri does, and
        // music lowers under it. In HomePad's session it took the audio from Apple
        // Music's player, which paused the song a request had just started.
        synthesizer.usesApplicationAudioSession = false
    }

    func speak(_ text: String) async throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = VoiceCatalog.voice(identifier: voiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate.multiplier
        await withCheckedContinuation { continuation in
            finished[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finishAll()
    }

    private func finish(_ id: ObjectIdentifier) {
        finished.removeValue(forKey: id)?.resume()
    }

    private func finishAll() {
        let pending = finished.values
        finished.removeAll()
        pending.forEach { $0.resume() }
    }
}

extension SystemSpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }
}
