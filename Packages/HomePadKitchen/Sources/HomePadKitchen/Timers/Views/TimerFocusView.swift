import HomePadCore
import HomePadUI
import SwiftUI

/// One timer, full size: the tick ring, a huge countdown, its label and total,
/// and cancel, +1 minute and pause or resume controls. Matches HomeView's timer.
struct TimerFocusView: View {
    let timer: HomeTimer
    var showsControls = true
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            LiveTime(isActive: timer.status == .running) { now in
                ZStack {
                    TickRing(progress: timer.progress(at: now))
                    GeometryReader { proxy in
                        let diameter = min(proxy.size.width, proxy.size.height)
                        VStack(spacing: diameter * 0.02) {
                            Text(timer.label)
                                .font(.system(size: diameter * 0.05, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            let seconds = Self.wholeSeconds(timer.remaining(at: now))
                            Text(TimerFormat.countdown(timer.remaining(at: now)))
                                .font(.display(diameter * 0.2))
                                .monospacedDigit()
                                // Each second rolls in, down while it counts and up for +1 min.
                                .contentTransition(.numericText(value: Double(seconds)))
                                .animation(reduceMotion ? nil : Self.roll, value: seconds)
                            Text(timer.statusText?.uppercased() ?? TimerFormat.total(timer.duration))
                                .font(.system(size: diameter * 0.05, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, diameter * 0.15)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(timer.label), \(TimerFormat.spoken(timer.remaining(at: now))) left")
            }
            if showsControls { controls }
        }
    }

    /// Shorter than `Theme.Motion.standard`, so a roll settles well before the next second.
    private static let roll: Animation = .smooth(duration: 0.3)

    /// The whole seconds the countdown shows, the value each roll follows.
    static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        Int(remaining.rounded(.up))
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.xl) {
            GlassIconButton("xmark", label: "Cancel timer") {
                services.timers.cancel(timer.id)
            }
            GlassCapsuleButton("+1 min", systemImage: "plus") {
                services.timers.add(60, to: timer.id)
            }
            switch timer.status {
            case .running, .paused:
                // One button, so pause turns into play instead of being swapped out.
                let isRunning = timer.status == .running
                GlassIconButton(isRunning ? "pause.fill" : "play.fill", label: isRunning ? "Pause" : "Resume", tint: .orange) {
                    withAnimation(Theme.Motion.standard) {
                        if isRunning { services.timers.pause(timer.id) } else { services.timers.resume(timer.id) }
                    }
                }
            case .finished:
                GlassIconButton("stop.fill", label: "Stop", tint: .orange) {
                    services.timers.cancel(timer.id)
                }
            }
        }
    }
}
