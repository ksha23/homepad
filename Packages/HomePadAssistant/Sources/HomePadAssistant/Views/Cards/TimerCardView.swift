import HomePadCore
import HomePadUI
import SwiftUI

/// Running timers with a live countdown.
struct TimerCardView: View {
    let card: AssistantCard

    var body: some View {
        let timers = card.payload["timers"]?.arrayValue ?? []
        // Paused and finished timers do not change, so only a running one ticks.
        let isRunning = timers.contains { $0["status"]?.stringValue == "running" }
        TimelineView(.periodic(from: .now, by: isRunning ? 1 : 3600)) { context in
            VStack(spacing: Theme.Spacing.m) {
                ForEach(Array(timers.enumerated()), id: \.offset) { _, timer in
                    GlassTile(tint: .orange) {
                        HStack {
                            Label(timer["label"]?.stringValue ?? "Timer", systemImage: "timer").font(.title2.weight(.semibold))
                            Spacer()
                            Text(remaining(timer, now: context.date)).font(.display(56)).monospacedDigit().foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func remaining(_ timer: JSONValue, now: Date) -> String {
        let end = timer["end"]?.doubleValue ?? 0
        let seconds = timer["status"]?.stringValue == "running" && end > 0
            ? max(0, end - now.timeIntervalSince1970)
            : timer["remaining"]?.doubleValue ?? 0
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
