import HomePadCore
import HomePadUI
import SwiftUI

/// Big timer chips for the times in a step ("3 to 5 minutes"). A chip whose
/// timer is already running shows its live countdown instead.
struct StepTimerChips: View {
    let context: KitchenContext
    let session: RecipeSession
    let step: RecipeStep
    @Environment(AppServices.self) private var services

    var body: some View {
        let durations = DurationExtractor.extract(from: step.text)
        if !durations.isEmpty {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(Array(durations.enumerated()), id: \.offset) { _, duration in
                    chip(for: duration)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for duration: DetectedDuration) -> some View {
        let label = session.timerLabel(for: step, duration: duration)
        if let running = services.timers.timers.first(where: { $0.label == label && $0.status != .finished }) {
            LiveTime(isActive: running.status == .running) { now in
                GlassCapsuleButton(TimerFormat.countdown(running.remaining(at: now)),
                                   systemImage: running.status == .paused ? "pause.fill" : "timer",
                                   size: .extraLarge, isProminent: true, tint: .orange) {
                    if running.status == .paused { services.timers.resume(running.id) } else { services.timers.pause(running.id) }
                }
            }
        } else {
            GlassCapsuleButton(duration.text, systemImage: "timer", size: .extraLarge) {
                context.startTimer(for: duration, in: step)
            }
            .accessibilityLabel("Start a \(duration.text) timer")
        }
    }
}
