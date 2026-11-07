import HomePadCore
import HomePadUI
import SwiftUI

/// One camera, large: name and "Live" on top, a LIVE badge on the video, close and
/// sound at the top corners, the grid button (every camera) and talk (when
/// supported) at the bottom. A swipe down closes it too, back to the Home app
/// or the camera grid as they were.
///
/// Sound plays from the start, and the speaker button shows once the feed has
/// sound. A Home Assistant camera that takes sound over WebRTC gets hold to
/// talk. HomeKit cameras with a speaker keep their talk toggle.
struct CameraFullScreenView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let camera: HomeCamera
    let onShowAll: () -> Void
    let onClose: () -> Void
    @State private var audio = CameraAudioControl(isMuted: false)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                header
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                CameraFeedView(camera: camera, purpose: .fullScreen, audio: audio)
                    .clipShape(shape)
                    .overlay(alignment: .topLeading) { StatusBadge.live.padding(Theme.Spacing.m) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    GlassIconButton("square.grid.2x2.fill", label: "All Cameras", size: Theme.Size.roundControl, action: onShowAll)
                    Spacer()
                    ExternalControlsLink(camera: camera)
                    Spacer()
                    talkButton
                }
            }
            .padding(Theme.Spacing.l)
            .fullScreenSurfaceContent()
        }
        // A camera is watched on black in every appearance, as in Apple Home.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .swipeDownToDismiss(onDismiss: onClose)
    }

    @ViewBuilder
    private var talkButton: some View {
        if audio.canHoldToTalk {
            HoldToTalkButton(audio: audio)
        } else if service.supportsTalk(cameraID: camera.id) {
            TalkButton(cameraID: camera.id)
        } else {
            Color.clear.frame(width: Theme.Size.roundControl, height: Theme.Size.roundControl)
        }
    }

    private var header: some View {
        DetailHeader(camera.name, subtitle: "Live", onClose: onClose, trailing: {
            if audio.hasAudio {
                GlassIconButton(audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                label: audio.isMuted ? "Unmute" : "Mute") { audio.isMuted.toggle() }
            }
        })
    }
}
