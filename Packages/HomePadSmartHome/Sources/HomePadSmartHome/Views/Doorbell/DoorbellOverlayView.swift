import HomePadCore
import HomePadUI
import SwiftUI

/// The full-screen front door view when the doorbell rings: the door, end, talk,
/// all cameras, and "Unlock Front Door". Guests must confirm before unlocking.
///
/// The door is live whenever this screen shows, from across the room and at
/// night too: a ring is when someone wants to see who is there and talk, and
/// stills there left no live view or talk until they walked up. Only a sleeping
/// display shows stills. The door's sound starts on, or muted at night, so a
/// late ring does not fill a dark room.
struct DoorbellOverlayView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services
    @Environment(\.displayCondition) private var displayCondition
    let presenter: DoorbellPresenter
    @State private var audio = CameraAudioControl(isMuted: false)

    private var isLive: Bool {
        displayCondition != .sleeping
    }

    var body: some View {
        ZStack {
            if let ring = presenter.ring {
                content(ring)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.4), value: presenter.ring)
        // Each ring starts with the door's sound on, or muted at night, whatever the last one was left at.
        .onChange(of: presenter.ring?.id) { audio.isMuted = displayCondition == .night }
    }

    private func content(_ ring: DoorbellPresenter.Ring) -> some View {
        let camera = service.camera(ring.cameraID)
        return ZStack {
            Color.black.ignoresSafeArea()
            if let camera {
                CameraFeedView(camera: camera, purpose: isLive ? .fullScreen : .still, audio: audio)
                    .environment(\.isDoorbellScreen, true)
                    .ignoresSafeArea()
            } else {
                CameraPlaceholder(message: "The doorbell camera is not available.", isLoading: false)
            }
            LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: Theme.Spacing.l) {
                VStack(spacing: 2) {
                    Text(camera?.name ?? "Front Door").font(.largeTitle.bold())
                    Text("Doorbell at \(ring.rangAt.formatted(date: .omitted, time: .shortened))\(isLive ? ", Live" : "")")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lock = service.doorbellLock {
                    UnlockDoorButton(lock: lock)
                }
                HStack(spacing: Theme.Spacing.xl) {
                    GlassIconButton("xmark", label: "Dismiss", size: Theme.Size.heroControl, tint: .red) {
                        presenter.dismiss()
                    }
                    if audio.canHoldToTalk {
                        HoldToTalkButton(audio: audio, size: Theme.Size.heroControl, onInteraction: presenter.noteInteraction)
                    } else if let camera, service.supportsTalk(cameraID: camera.id) {
                        TalkButton(cameraID: camera.id, size: Theme.Size.heroControl)
                    }
                    if audio.hasAudio {
                        GlassIconButton(audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                        label: audio.isMuted ? "Unmute" : "Mute", size: Theme.Size.heroControl) {
                            audio.isMuted.toggle()
                        }
                    }
                    GlassIconButton("square.grid.2x2.fill", label: "All Cameras", size: Theme.Size.heroControl) {
                        presenter.dismiss()
                        services.events.post(.openApp(id: SmartHomeModule.camerasAppID))
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .foregroundStyle(.white)
        // The live front door fills the screen, so its text and glass stay light
        // on dark in every appearance.
        .environment(\.colorScheme, .dark)
        .simultaneousGesture(TapGesture().onEnded { presenter.noteInteraction() })
        .nightModeAware()
        .accessoryCommandHost()
    }
}
