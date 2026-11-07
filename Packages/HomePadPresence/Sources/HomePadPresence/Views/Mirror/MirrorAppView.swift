import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// The Mirror app: the front camera full screen with an edge ring light and a
/// close-up or full-body view, like HomeView's Mirror. Where the camera has
/// Center Stage, a Close-Up and Full Body switch drives it. Elsewhere a 2× or
/// 1× zoom button stands in.
struct MirrorAppView: View {
    @Environment(AppServices.self) private var services
    @State private var camera = MirrorCamera()
    @State private var savedBrightness: CGFloat?

    var body: some View {
        let settings = services.settings
        let level = settings[PresenceSettings.mirrorRingLight]
        let tone = settings[PresenceSettings.mirrorRingTone]
        let framing = settings[PresenceSettings.mirrorFraming]

        RingLightView(level: level, tone: tone) {
            preview(framing: framing)
                .overlay(alignment: .bottom) {
                    controls(level: level, tone: tone, framing: framing)
                        .padding(Theme.Spacing.l)
                }
        }
        // Dark in Light too, like the Camera app: the picture is the front camera,
        // and the controls over it are dark glass with white symbols.
        .environment(\.colorScheme, .dark)
        .task { camera.open(services: services, framing: framing) }
        .onDisappear {
            camera.close(services: services)
            setScreenBoost(false)
        }
        .onChange(of: level, initial: true) { _, newLevel in setScreenBoost(newLevel.boostsScreen) }
        .onChange(of: framing) { _, newFraming in camera.setFraming(newFraming) }
    }

    @ViewBuilder
    private func preview(framing: MirrorFraming) -> some View {
        switch camera.state {
        case .running:
            CameraPreview(session: camera.camera.session, device: camera.device)
        case .needsPermission:
            explanation(framing: framing)
        case .denied:
            PermissionPrompt(
                "Camera Access Is Off", message: "Allow camera access for HomePad in Settings to use Mirror.",
                systemImage: "camera.fill", state: .denied
            )
            .background(.black)
        case .blocked:
            EmptyStateView(
                "Camera Unavailable",
                message: "Turn on the camera in Control Center, or close the feature that is using it.",
                systemImage: "video.slash.fill"
            )
            .background(.black)
        case .noCamera:
            simulatorPlaceholder
        case .idle:
            Color.black
        }
    }

    private func explanation(framing: MirrorFraming) -> some View {
        EmptyStateView(
            "Use the Front Camera as a Mirror",
            message: "Mirror shows the front camera on screen. Video stays on this iPad and is never recorded.",
            systemImage: "person.crop.rectangle", actionTitle: "Continue"
        ) {
            Task { await camera.requestAccess(services: services, framing: framing) }
        }
        .background(.black)
    }

    /// The simulator has no camera, so show a calm stand-in that keeps the
    /// ring light and controls testable.
    private var simulatorPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.3), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 120, weight: .light))
                Text("The front camera preview appears here on iPad.")
                    .font(.title3)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func controls(level: RingLightLevel, tone: RingLightTone, framing: MirrorFraming) -> some View {
        HStack {
            if camera.supportsCenterStage {
                // Center Stage frames the person for Close-Up, and steps back for Full Body.
                MirrorFramingSwitch(framing: services.settings.binding(PresenceSettings.mirrorFraming))
            } else {
                Button {
                    services.settings[PresenceSettings.mirrorFraming] = framing == .closeUp ? .wide : .closeUp
                } label: {
                    Text(framing == .closeUp ? "2×" : "1×")
                        .monospacedDigit()
                }
                .buttonStyle(.glassIcon())
                .accessibilityLabel(framing == .closeUp ? "Switch to wide view" : "Switch to close-up")
            }

            Spacer()

            Menu {
                Picker("Ring Light", selection: services.settings.binding(PresenceSettings.mirrorRingLight)) {
                    ForEach(RingLightLevel.allCases) { Text($0.title).tag($0) }
                }
                Picker("Light Color", selection: services.settings.binding(PresenceSettings.mirrorRingTone)) {
                    ForEach(RingLightTone.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Ring Light", systemImage: level == .off ? "lightbulb" : "lightbulb.fill")
            }
            .buttonStyle(.glassIcon())
            .accessibilityLabel("Ring light, \(level.title), \(tone.title)")
        }
    }

    /// Full screen brightness makes the ring light bright enough to light a face.
    private func setScreenBoost(_ on: Bool) {
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }
}
