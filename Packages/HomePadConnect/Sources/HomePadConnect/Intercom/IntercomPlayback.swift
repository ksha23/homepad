#if os(iOS)
import AVFoundation
import HomePadCore

/// Plays intercom clips and speaks text announcements, holding a `.playback`
/// claim on the shared audio session only while sound is coming out.
@MainActor
final class IntercomPlayback: NSObject {
    private let audioSession: AudioSessionCoordinator
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: (() -> Void)?
    private static let owner = "connect.intercom"

    init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
        super.init()
        synthesizer.delegate = self
    }

    /// Plays an .m4a file. `completion` runs when it ends or fails.
    func play(_ url: URL, completion: @escaping () -> Void) {
        stop()
        audioSession.claim(.playback, owner: Self.owner)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            finished = completion
            player.play()
        } catch {
            Log.make("Intercom").error("Playback failed: \(error.localizedDescription, privacy: .public)")
            done()
            completion()
        }
    }

    /// Speaks "<from> says <text>".
    func speak(_ text: String, from name: String, completion: @escaping () -> Void) {
        stop()
        audioSession.claim(.playback, owner: Self.owner)
        finished = completion
        let utterance = AVSpeechUtterance(string: "\(name) says: \(text)")
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
    }

    func stop() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        done()
    }

    private func done() {
        audioSession.release(owner: Self.owner)
        let callback = finished
        finished = nil
        callback?()
    }
}

extension IntercomPlayback: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.done() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.done() }
    }
}
#endif
