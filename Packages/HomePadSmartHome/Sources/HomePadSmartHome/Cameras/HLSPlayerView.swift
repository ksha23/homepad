import AVFoundation
import HomePadCore
import SwiftUI

/// Plays an HLS playlist through `AVPlayerLayer`. Its sound plays when the
/// screen's control is unmuted, under a `.playback` claim held only while it is
/// heard. Calls `onFailure` when the item cannot play, so the caller can fall back.
struct HLSPlayerView: UIViewRepresentable {
    let url: URL
    var audio: CameraAudioControl?
    var onFailure: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.cameraContentMode) private var contentMode

    private var gravity: AVLayerVideoGravity { contentMode == .fit ? .resizeAspect : .resizeAspectFill }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        context.coordinator.attach(player: player, audioSession: services.audioSession, audio: audio)
        context.coordinator.observe(item)
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.videoGravity = gravity
        context.coordinator.onFailure = onFailure
        context.coordinator.isMuted = audio?.isMuted ?? true
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        view.playerLayer.player = nil
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    @MainActor
    final class Coordinator {
        var onFailure: () -> Void
        var isMuted = true {
            didSet { applySound() }
        }
        private var observations: [NSKeyValueObservation] = []
        private weak var player: AVPlayer?
        private var audioSession: AudioSessionCoordinator?
        private var audio: CameraAudioControl?
        private var hasAudio = false
        private var isClaimed = false
        /// Each player holds its own claim.
        private let owner = "smarthome.camera.hls.\(UUID().uuidString)"

        init(onFailure: @escaping () -> Void) {
            self.onFailure = onFailure
        }

        func attach(player: AVPlayer, audioSession: AudioSessionCoordinator, audio: CameraAudioControl?) {
            self.player = player
            self.audioSession = audioSession
            self.audio = audio
            isMuted = audio?.isMuted ?? true
            report()
        }

        func observe(_ item: AVPlayerItem) {
            observations = [
                item.observe(\.status) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    DispatchQueue.main.async { self?.onFailure() }
                },
                // The playlist's tracks arrive after it loads. A camera without a microphone has none for sound.
                item.observe(\.tracks) { [weak self] item, _ in
                    let hasAudio = item.tracks.contains { $0.assetTrack?.mediaType == .audio }
                    DispatchQueue.main.async { self?.setHasAudio(hasAudio) }
                },
            ]
        }

        func detach() {
            observations = []
            if let audio { audio.release(owner: ObjectIdentifier(self)) }
            hasAudio = false
            applySound()
        }

        private func setHasAudio(_ value: Bool) {
            guard value != hasAudio else { return }
            hasAudio = value
            report()
            applySound()
        }

        private func report() {
            audio?.update(owner: ObjectIdentifier(self), hasAudio: hasAudio, canTalk: false, isTalking: false) { _ in }
        }

        private func applySound() {
            let audible = hasAudio && !isMuted
            player?.isMuted = !audible
            guard audible != isClaimed, let audioSession else { return }
            isClaimed = audible
            if audible { audioSession.claim(.playback, owner: owner) } else { audioSession.release(owner: owner) }
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
