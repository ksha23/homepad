import HomePadCore
import HomePadUI
import SwiftUI

/// Full-screen alert while a timer is done: a big glowing ring, Stop and +1 min,
/// and a looping chime. Shows over everything, including faces and night mode.
struct TimerFinishedOverlay: View {
    let context: KitchenContext
    @Environment(AppServices.self) private var services
    @State private var glow = false
    @Environment(\.allowsContinuousMotion) private var allowsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var finished: [HomeTimer] {
        services.timers.timers.filter { $0.status == .finished }
    }

    var body: some View {
        let finished = finished
        ZStack {
            if let timer = finished.first {
                alert(for: timer, others: finished.count - 1)
                    .transition(.fullScreenSurface(scale: 1.04))
            }
        }
        .animation(Theme.Motion.screen, value: finished.map(\.id))
        .onChange(of: !finished.isEmpty, initial: true) { _, isRinging in
            updateChime(isRinging: isRinging)
        }
    }

    private func alert(for timer: HomeTimer, others: Int) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                ZStack {
                    // Breathes while someone may be watching. It holds still when the
                    // display dims, since a timer can ring for a long time unheard.
                    // Reduce Motion shows the whole ring, lit and still.
                    let breathes = glow && allowsMotion && !reduceMotion
                    TickRing(progress: 1)
                        .scaleEffect(reduceMotion ? 1 : (breathes ? 1.03 : 0.97))
                        .opacity(reduceMotion || breathes ? 1 : 0.6)
                        .animation(breathes ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : Theme.Motion.standard, value: breathes)
                    VStack(spacing: Theme.Spacing.s) {
                        Text(timer.label)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text("Done")
                            .font(.display(120))
                        LiveTime { now in
                            Text("\(TimerFormat.countdown(now.timeIntervalSince(timer.endDate ?? now))) ago")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .frame(maxWidth: 560, maxHeight: 560)

                HStack(spacing: Theme.Spacing.l) {
                    GlassCapsuleButton("+1 min", systemImage: "plus", size: .extraLarge) {
                        services.timers.add(60, to: timer.id)
                    }
                    GlassCapsuleButton("Stop", systemImage: "stop.fill", size: .extraLarge, isProminent: true, tint: .orange) {
                        services.timers.cancel(timer.id)
                    }
                }
                if others > 0 {
                    GlassCapsuleButton("Stop All \(others + 1) Timers") {
                        finished.forEach { services.timers.cancel($0.id) }
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .fullScreenSurfaceContent()
        }
        .onAppear { glow = true }
        // A dark alert in every appearance, like the Clock app's, so it rings
        // the same by day and by night and reads from across the room.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .accessibilityAddTraits(.isModal)
    }

    private func updateChime(isRinging: Bool) {
        if isRinging {
            services.events.post(.wake)
            context.chime.ring(services.settings[KitchenSettings.chime], audioSession: services.audioSession)
        } else {
            context.chime.stop()
        }
    }
}
