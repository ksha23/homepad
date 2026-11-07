import HomePadCore
import HomePadUI
import SwiftUI

/// The shared camera feed in a rounded frame with a "Live" or "Demo Feed"
/// badge, like HomeView's camera views. Tools layer their own controls on top.
/// It stays dark in Light, like the Camera app: the picture sits on black, and
/// the controls over it are dark glass with white symbols.
struct CameraViewport<Overlay: View>: View {
    @Environment(CameraLab.self) private var lab
    private let overlay: Overlay

    init(@ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.overlay = overlay()
    }

    var body: some View {
        ZStack {
            Color.black
            feed
            statusMessage
            overlay
        }
        .overlay(alignment: .topLeading) {
            if lab.broker.status == .running {
                StatusBadge(lab.broker.isDemo ? "Demo Feed" : "Live", color: lab.broker.isDemo ? .orange : .red)
                    .padding(Theme.Spacing.m)
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .nightModeAware()
    }

    @ViewBuilder
    private var feed: some View {
        if let live = lab.broker.liveSession {
            CameraPreview(session: live.session, device: live.device)
        } else if lab.broker.isDemo, lab.broker.status == .running, let hub = lab.broker.hub {
            // Polls eight times a second, so only while the demo feed runs.
            DemoFeedView(hub: hub)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch lab.broker.status {
        case .starting:
            ProgressView().controlSize(.large)
        case .interrupted(let message), .failed(let message):
            Label(message, systemImage: "video.slash")
                .font(.title3)
                .padding(Theme.Spacing.l)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        case .stopped, .running:
            EmptyView()
        }
    }
}

/// Claims a camera while the view is on screen and releases it when it leaves.
/// The result lands in `access` so the view can show why the camera is unavailable.
///
/// The display going to sleep counts as leaving: a tool left open would
/// otherwise run the camera all night under the sleeping screen, and keep
/// presence sensing, which yields to it, from seeing anyone come back.
/// Waking claims the camera again.
struct CameraHoldModifier: ViewModifier {
    @Environment(CameraLab.self) private var lab
    @Environment(\.displayCondition) private var condition
    let owner: String
    let title: String
    let camera: CameraPosition
    var usesSystemCapture = false
    @Binding var access: CameraBroker.Access?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if condition != .sleeping { acquire() }
            }
            .onDisappear {
                lab.broker.release(owner)
            }
            .onChange(of: condition == .sleeping) { _, isAsleep in
                if isAsleep {
                    lab.broker.release(owner)
                    // Removes a live scanner, which runs its own capture session.
                    access = nil
                } else {
                    acquire()
                }
            }
    }

    private func acquire() {
        access = lab.broker.acquire(owner, title: title, camera: camera, usesSystemCapture: usesSystemCapture)
    }
}

extension View {
    /// See `CameraHoldModifier`.
    func holdsCamera(_ owner: String, title: String, camera: CameraPosition = .back, usesSystemCapture: Bool = false,
                     access: Binding<CameraBroker.Access?>) -> some View {
        modifier(CameraHoldModifier(owner: owner, title: title, camera: camera, usesSystemCapture: usesSystemCapture, access: access))
    }
}
