import AVFoundation
import HomePadCore

/// Plays a chime on a loop while a finished timer or a wake-up alarm is on
/// screen, holding a `.playback` claim on the shared audio session. Rings for at
/// most ten minutes so an empty kitchen is not filled with sound all evening.
@MainActor
final class ChimePlayer {
    /// Its claim on the audio session. Timers and alarms each have their own,
    /// so one stopping never silences the other.
    let owner: String
    private static let maximumRingTime: Duration = .seconds(600)

    private var player: AVAudioPlayer?
    private weak var audioSession: AudioSessionCoordinator?
    private var cutoff: Task<Void, Never>?
    private let log = Log.make("Kitchen.Chime")

    init(owner: String = "kitchen.timerChime") {
        self.owner = owner
    }

    /// Starts looping `sound`. Calling it while already ringing does nothing.
    func ring(_ sound: ChimeSound, audioSession: AudioSessionCoordinator) {
        if let player, player.isPlaying, player.numberOfLoops < 0 { return }
        stop()
        play(sound, loops: -1, audioSession: audioSession)
        cutoff = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumRingTime)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Plays `sound` once, for choosing a chime in Settings.
    func preview(_ sound: ChimeSound, audioSession: AudioSessionCoordinator) {
        stop()
        play(sound, loops: 0, audioSession: audioSession)
        cutoff = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sound.pattern.loopLength + 0.2))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        cutoff?.cancel()
        cutoff = nil
        player?.stop()
        player = nil
        audioSession?.release(owner: owner)
    }

    private func play(_ sound: ChimeSound, loops: Int, audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
        audioSession.claim(.playback, owner: owner)
        do {
            let player = try AVAudioPlayer(data: ChimeSynthesizer.wav(for: sound), fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = loops
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            log.error("Chime failed: \(error.localizedDescription, privacy: .public)")
            audioSession.release(owner: owner)
        }
    }
}
