import HomePadUI
import SwiftUI

/// A small pill at the top center of every screen while Security Camera is
/// watching, where the camera-in-use dot sits on iPad, so nobody is filmed
/// without knowing. Registered as an overlay.
struct SecurityIndicatorOverlay: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        if lab.security.isWatching {
            VStack {
                StatusBadge("Security Camera On", color: .red, pulses: true)
                    // A dark pill with white text on every screen, light or dark.
                    // Glass alone turned light gray over a white page, and the
                    // warning has to read over pages, faces and photos alike.
                    .environment(\.colorScheme, .dark)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.top, Theme.Spacing.xs)
                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// The Control Center tile that turns Security Camera mode on and off.
struct SecurityControlTile: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        let security = lab.security
        Button {
            security.setEnabled(!security.isEnabled)
        } label: {
            GlassTile(isHighlighted: security.isEnabled, tint: .red) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Image(systemName: security.isEnabled ? "video.badge.waveform.fill" : "video.slash")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 0)
                    Text("Security Camera").font(.headline)
                    Text(security.isEnabled ? (security.isWatching ? "Watching" : "Scheduled") : "Off")
                        .font(.tileDetail)
                        .opacity(0.8)
                }
                .foregroundStyle(security.isEnabled ? Color.black : Color.primary)
            }
            // The red fills in as the text and symbol change with it.
            .animation(Theme.Motion.standard, value: security.isEnabled)
        }
        .buttonStyle(.pressable(scale: 0.97))
        .accessibilityLabel("Security Camera")
        .accessibilityValue(security.isEnabled ? "On" : "Off")
    }
}
