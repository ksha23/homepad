import HomePadCore
import HomePadUI
import SwiftUI

/// The soonest running timer as a small capsule, like HomeView's timer pill:
/// a tick ring that empties as it counts and the time left, with "+2" when
/// more timers are on. Tapping opens Timers. A finished timer leaves the pill
/// to Kitchen's full-screen alert.
///
/// The countdown redraws once a second, on the second it changes, and only
/// while the pill is on screen and the timer runs. A paused timer is drawn once.
struct TimerPill: View {
    let timer: HomeTimer
    /// How many other timers run or are paused.
    let others: Int
    /// As tall as `minTapTarget`, else `TopPills.largeHeight`.
    let isCompact: Bool
    @Environment(ShellNavigator.self) private var navigator
    @Environment(\.displayCondition) private var condition

    var body: some View {
        Button(action: open) {
            Group {
                if timer.status == .running, let end = timer.endDate {
                    TimelineView(CountdownSchedule(end: end)) { context in
                        label(at: context.date)
                    }
                } else {
                    label(at: Date())
                }
            }
            .padding(.leading, Theme.Spacing.xs)
            .padding(.trailing, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: isCompact ? Theme.Size.minTapTarget : TopPills.largeHeight)
        }
        .buttonStyle(.plain)
        .topPillBackground()
        // Timers opened from the pill closes back into it.
        .zoomSource(ZoomSourceID.pill(KnownAppID.timers), shape: .capsule)
        .accessibilityHint("Opens Timers")
    }

    private func label(at now: Date) -> some View {
        let remaining = timer.remaining(at: now)
        return HStack(spacing: Theme.Spacing.xs) {
            ring(progress: timer.duration > 0 ? remaining / timer.duration : 0)
            Text(Self.countdown(remaining))
                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                .monospacedDigit()
                .foregroundStyle(timer.status == .paused ? quiet : Color.orange)
            if others > 0 {
                Text("+\(others)")
                    .font(isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(quiet)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(for: timer, remaining: remaining, others: others))
    }

    /// HomeView's tick ring, small, with a pause symbol inside while paused.
    private func ring(progress: Double) -> some View {
        let side: CGFloat = isCompact ? 30 : 40
        return TickRing(progress: progress, tint: timer.status == .paused ? quiet : .orange,
                        tickCount: 20, tickWidthRatio: 0.07, tickLengthRatio: 0.24)
            .overlay {
                if timer.status == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: side * 0.3, weight: .bold))
                        .foregroundStyle(quiet)
                }
            }
            .frame(width: side, height: side)
    }

    /// Gray for "+2" and a paused timer. At night the red tint would all but
    /// hide gray, so it is white there and turns red with the rest.
    /// Plain colors: the adaptive styles take on the colors behind the glass.
    private var quiet: Color {
        condition == .night ? .white : .white.opacity(0.75)
    }

    private func open() {
        navigator.open(appID: KnownAppID.timers)
    }
}

extension TimerPill {
    /// "4:47", "14:47" or "1:04:47", like the timer in the Dynamic Island.
    /// Rounds up, so a running timer never shows 0:00.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let pattern: Duration.TimeFormatStyle.Pattern = total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
    }

    /// "Pasta, 14 minutes, 47 seconds left, and 2 more timers".
    static func spokenLabel(for timer: HomeTimer, remaining: TimeInterval, others: Int) -> String {
        let left = Duration.seconds(Int(max(0, remaining).rounded(.up)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        var parts = [timer.label]
        if timer.status == .paused { parts.append("paused") }
        parts.append("\(left) left")
        if others > 0 { parts.append("and \(others) more \(others == 1 ? "timer" : "timers")") }
        return parts.joined(separator: ", ")
    }
}

/// One entry now, then one on each whole second before `end`, which is when a
/// countdown rounded up changes. Nothing after the end: the timer service
/// marks the timer finished and the pill goes.
struct CountdownSchedule: TimelineSchedule {
    let end: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var startPending = true
        var secondsBeforeEnd = Int(end.timeIntervalSince(startDate).rounded(.down))
        return AnyIterator {
            if startPending {
                startPending = false
                return startDate
            }
            while secondsBeforeEnd >= 0 {
                let date = end.addingTimeInterval(-Double(secondsBeforeEnd))
                secondsBeforeEnd -= 1
                if date > startDate { return date }
            }
            return nil
        }
    }
}
