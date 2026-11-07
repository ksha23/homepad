import AVFoundation
import Foundation

/// Reads text with the Natural voice: Kokoro audio played through an AVAudioEngine
/// on the app's audio session. While one sentence plays, the next is made
/// (`prepare`), so sentences follow each other without a gap.
@MainActor
final class NaturalSpeechOutput: SpeechOutput {
    var voice: NaturalVoice = .heart
    var rate: SpeakingRate = .normal

    private let engine: KokoroEngine
    private let audio = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroEngine.sampleRate, channels: 1)!
    private var prepared: [String: Task<[Float], Error>] = [:]
    private var playing: CheckedContinuation<Void, Never>?
    private var idleStop: Task<Void, Never>?

    init(engine: KokoroEngine) {
        self.engine = engine
        audio.attach(player)
        audio.connect(player, to: audio.mainMixerNode, format: format)
    }

    func prepare(_ text: String) {
        guard prepared[text] == nil else { return }
        prepared[text] = synthesis(of: text)
    }

    func speak(_ text: String) async throws {
        let task = prepared.removeValue(forKey: text) ?? synthesis(of: text)
        let samples = try await task.value
        try Task.checkCancellation()
        try await play(samples)
    }

    func stop() {
        prepared.values.forEach { $0.cancel() }
        prepared.removeAll()
        player.stop()
        finishPlaying()
    }

    private func synthesis(of text: String) -> Task<[Float], Error> {
        let engine = engine, key = voice.fileKey, speed = rate.multiplier
        return Task { try await engine.synthesize(text, voice: key, speed: speed) }
    }

    private func play(_ samples: [Float]) async throws {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        idleStop?.cancel()
        if !audio.isRunning { try audio.start() }
        await withCheckedContinuation { continuation in
            playing = continuation
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finishPlaying() }
            }
            player.play()
        }
        stopWhenIdle()
    }

    private func finishPlaying() {
        playing?.resume()
        playing = nil
    }

    /// Stops the audio engine shortly after the last sentence, unless another follows.
    private func stopWhenIdle() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.player.stop()
            self.audio.stop()
        }
    }
}
