import AVKit
import HomePadCore
import SwiftUI

/// A library video with the system's playback controls. It loads as soon as it
/// is drawn, but plays only while `isActive`: the viewer loads the videos next
/// to the one on screen ahead, and those wait, paused and silent, until they
/// come on. It stops when it goes, so a video paged away from never keeps playing.
///
/// While it plays its sound claims `.playback`, as chimes and spoken answers
/// do: it mixes with music instead of stopping it, and the microphone keeps
/// listening for the wake word.
struct PhotoVideoPlayer: View {
    let id: String
    /// True for the video on screen. Turning it off pauses the video and gives the audio back.
    var isActive = true
    /// Called when the video plays to its end, so a slideshow can move on.
    var onFinished: () -> Void = {}

    @Environment(PhotoLibraryService.self) private var photos
    @Environment(AppServices.self) private var services
    @State private var player: AVPlayer?
    @State private var failed = false

    /// One owner per video, so a neighbour letting go never ends the claim of the one playing.
    private var owner: String { "personal.photos.video.\(id)" }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if failed {
                ContentUnavailableView("Video Unavailable", systemImage: "video.slash",
                                       description: Text("This video could not be loaded."))
                    .background(.black)
            } else if isActive {
                // The viewer draws the video's first frame underneath while it loads.
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .task(id: id) { await load() }
        .onChange(of: isActive) { _, active in
            if active { play() } else { pause() }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard isActive, let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            onFinished()
        }
    }

    private func load() async {
        guard let item = await photos.playerItem(for: id) else {
            failed = true
            return
        }
        player = AVPlayer(playerItem: item)
        if isActive { play() }
    }

    private func play() {
        guard let player else { return }
        services.audioSession.claim(.playback, owner: owner)
        player.play()
    }

    private func pause() {
        player?.pause()
        services.audioSession.release(owner: owner)
    }

    private func stop() {
        pause()
        player = nil
    }
}
