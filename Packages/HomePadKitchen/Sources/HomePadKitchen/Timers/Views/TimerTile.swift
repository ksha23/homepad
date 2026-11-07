import HomePadCore
import HomePadUI
import SwiftUI

/// A timer as a tile in the Timers app: a small ring with pause or resume and
/// cancel, then the countdown in large numerals and the label. Tap it to show
/// it in the big ring.
struct TimerTile: View {
    let timer: HomeTimer
    var isSelected = false
    let onSelect: () -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        LiveTime(isActive: timer.status == .running) { now in
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    TickRing(progress: timer.progress(at: now), tickCount: 20, tickWidthRatio: 0.07, tickLengthRatio: 0.24)
                        .frame(width: 52, height: 52)
                    Spacer(minLength: 0)
                    controls
                }
                Text(TimerFormat.countdown(timer.remaining(at: now)))
                    .font(.display(48))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(timer.statusText.map { "\(timer.label) · \($0)" } ?? timer.label)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.orange.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .onTapGesture(perform: onSelect)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.status {
        case .running, .paused:
            // One button, so pause turns into play instead of being swapped out.
            let isRunning = timer.status == .running
            GlassIconButton(isRunning ? "pause.fill" : "play.fill", label: "\(isRunning ? "Pause" : "Resume") \(timer.label)",
                            size: Theme.Size.tapTarget) {
                withAnimation(Theme.Motion.standard) {
                    if isRunning { services.timers.pause(timer.id) } else { services.timers.resume(timer.id) }
                }
            }
        case .finished:
            EmptyView()
        }
        GlassIconButton("xmark", label: "Cancel \(timer.label)", size: Theme.Size.tapTarget) {
            services.timers.cancel(timer.id)
        }
    }
}
