import HomePadCore
import HomePadUI
import SwiftUI

/// Sound alerts above everything: a full-screen red takeover for smoke or CO
/// alarms, and a short glass banner for other sounds.
struct SoundAlertOverlay: View {
    let sounds: SoundAlertService

    var body: some View {
        ZStack(alignment: .top) {
            if let banner = sounds.banner, sounds.activeAlarm == nil {
                GlassBanner(
                    systemImage: banner.kind.systemImage,
                    title: banner.kind.title,
                    subtitle: "Heard \(banner.time.formatted(date: .omitted, time: .shortened))"
                )
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let alarm = sounds.activeAlarm {
                AlarmTakeover(alarm: alarm) { sounds.dismissAlarm() }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.4), value: sounds.banner)
        .animation(.smooth(duration: 0.4), value: sounds.activeAlarm)
    }
}

/// The full-screen life-safety alert. Deliberately unmissable from across a room.
private struct AlarmTakeover: View {
    let alarm: SoundAlert
    let dismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            Color.black.opacity(pulse ? 0.25 : 0).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 120, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating)
                VStack(spacing: Theme.Spacing.s) {
                    Text(alarm.kind.alertHeadline)
                        .font(.display(64, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("HomePad heard an alarm at \(alarm.time.formatted(date: .omitted, time: .shortened)). Check your home and get to safety if needed.")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                    Text("Sound recognition can miss alarms. Never rely on it in an emergency.")
                        .font(.callout)
                        .opacity(0.8)
                }
                GlassCapsuleButton("Dismiss", size: .extraLarge, action: dismiss)
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.xl)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        // The same in Light and Dark: white on red, with dark glass for Dismiss.
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
    }
}
