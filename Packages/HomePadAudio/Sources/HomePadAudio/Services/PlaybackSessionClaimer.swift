import Foundation
import HomePadCore

/// Claims the shared audio session for what plays in HomePad's own session:
/// radio, sleep sounds and the simulator demo. Apple Music and the library play
/// in Apple's own player, which has its own session, so they claim nothing
/// (`AudioMediaService.prepareToPlay`).
///
/// By default it claims `.longFormPlayback`, which lets the system picker offer
/// AirPlay 2 multi-room (several HomePods at once). `AudioSessionCoordinator`
/// pauses recording for that, so the microphone is suspended first and resumed
/// once playback ends. With "Keep microphone on" it claims `.mediaPlayback` instead,
/// and the coordinator lands in `.playAndRecord`: the wake word keeps working,
/// but only one AirPlay speaker can play.
@MainActor
final class PlaybackSessionClaimer {
    static let owner = "audio.media"
    /// Short pauses keep the claim so resuming never re-negotiates the AirPlay route.
    static let releaseDelay: Duration = .seconds(20)

    private unowned let services: AppServices
    private(set) var claimed: AudioSessionCoordinator.Need?
    private var releaseTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    nonisolated static func need(preferMicrophone: Bool) -> AudioSessionCoordinator.Need {
        preferMicrophone ? .mediaPlayback : .longFormPlayback
    }

    /// Claims (or re-claims after a settings change) before playback starts.
    func claim() {
        releaseTask?.cancel()
        releaseTask = nil
        let need = Self.need(preferMicrophone: services.settings[AudioSettings.preferMicrophone])
        guard need != claimed else { return }
        if need == .longFormPlayback { services.microphone.suspend() }
        services.audioSession.claim(need, owner: Self.owner)
        let wasLongForm = claimed == .longFormPlayback
        claimed = need
        if wasLongForm { resumeMicrophoneIfAllowed() }
    }

    /// Releases after `releaseDelay`, unless playback resumes first.
    func releaseSoon() {
        guard claimed != nil, releaseTask == nil else { return }
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseDelay)
            guard !Task.isCancelled else { return }
            self?.release()
        }
    }

    func release() {
        releaseTask?.cancel()
        releaseTask = nil
        guard let previous = claimed else { return }
        services.audioSession.release(owner: Self.owner)
        claimed = nil
        if previous == .longFormPlayback { resumeMicrophoneIfAllowed() }
    }

    private func resumeMicrophoneIfAllowed() {
        guard services.settings[CoreSettings.microphoneEnabled], services.microphone.subscriberCount > 0 else { return }
        services.microphone.resume()
    }
}
