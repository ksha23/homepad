import HomePadCore
import HomePadUI
import SwiftUI

/// The Security Camera screen: the live view with a motion meter, recent
/// motion snapshots, and the mode's settings and Home Assistant setup values.
struct SecurityCameraView: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        let security = lab.security
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                viewport
                MotionSnapshotStrip()
            }
            .frame(maxWidth: .infinity)
            Form {
                SecurityStatusSection()
                SecurityScheduleSection()
                SecurityDetectionSection()
                SecurityStreamSection()
                SecurityWebhookSection()
            }
            .scrollContentBackground(.hidden)
            .frame(width: 440)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .animation(.smooth, value: security.isWatching)
    }

    @ViewBuilder
    private var viewport: some View {
        let security = lab.security
        if security.isWatching {
            CameraViewport {
                VStack {
                    Spacer()
                    HStack {
                        MotionMeter()
                        Spacer()
                        if security.viewerCount > 0 {
                            StatusBadge("\(security.viewerCount) watching", color: .blue)
                        }
                    }
                    .padding(Theme.Spacing.m)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            GlassTile {
                EmptyStateView(
                    security.isEnabled ? "Waiting for Schedule" : "Security Camera Is Off",
                    message: security.isEnabled ? security.schedule.detail : "Turn it on to watch for motion, keep snapshots and stream to Home Assistant. Presence sensing pauses while it watches.",
                    systemImage: security.isEnabled ? "moon.zzz" : "video.slash",
                    actionTitle: security.isEnabled ? nil : "Turn On",
                    action: security.isEnabled ? nil : { security.setEnabled(true) }
                )
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }
}

/// A slim bar showing how much of the frame is changing right now. It reads the
/// level itself: the level changes five times a second, and read by the screen
/// it redrew the whole screen and its settings form each time.
struct MotionMeter: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        let level = lab.security.motionLevel
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "figure.walk.motion")
            Capsule()
                .fill(.primary.opacity(0.2))
                .frame(width: 140, height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(level > 0.01 ? Color.orange : Color.green)
                        .frame(width: max(8, 140 * min(1, level * 8)), height: 8)
                }
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: Capsule())
        .animation(.smooth(duration: 0.2), value: level)
        .accessibilityLabel("Motion level")
        .accessibilityValue("\(Int(level * 100)) percent of the picture is changing")
    }
}
