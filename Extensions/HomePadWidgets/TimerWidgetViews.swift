import HomePadCore
import SwiftUI
import WidgetKit

/// Shared pieces for the Live Activity and the Home Screen widget. The extension
/// only links HomePadCore, so these mirror the app's timer styling in miniature.
enum TimerWidgetStyle {
    static let tint = Color.orange
}

/// A live countdown for running timers, a fixed time for paused ones, "Done" when over.
struct TimerCountdownText: View {
    let entry: TimerActivityAttributes.Entry
    /// The moment the widget renders, so ended timers read "Done" even before the app updates.
    var now = Date()

    var body: some View {
        if entry.status == .finished || (entry.status == .running && (entry.endDate ?? now) <= now) {
            Text("Done")
        } else if entry.status == .running, let end = entry.endDate {
            Text(timerInterval: now...end, countsDown: true)
        } else {
            Text(Self.format(entry.remaining(at: now)))
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// A circular progress ring that drains on its own while a timer runs.
struct TimerRing: View {
    let entry: TimerActivityAttributes.Entry
    var now = Date()

    var body: some View {
        Group {
            if entry.status == .running, let end = entry.endDate, end > now {
                ProgressView(timerInterval: end.addingTimeInterval(-max(entry.duration, 1))...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
            } else {
                ProgressView(value: entry.duration > 0 ? entry.remaining(at: now) / entry.duration : 0)
                    .progressViewStyle(.circular)
            }
        }
        .tint(TimerWidgetStyle.tint)
        .overlay {
            Image(systemName: entry.status == .paused ? "pause.fill" : "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TimerWidgetStyle.tint)
        }
    }
}

/// One timer as a row: ring, label, countdown.
struct TimerEntryRow: View {
    let entry: TimerActivityAttributes.Entry
    var now = Date()
    var countdownFont: Font = .title2

    var body: some View {
        HStack(spacing: 10) {
            TimerRing(entry: entry, now: now)
                .frame(width: 28, height: 28)
            Text(entry.label)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            TimerCountdownText(entry: entry, now: now)
                .font(countdownFont.weight(.semibold).monospacedDigit())
                .foregroundStyle(TimerWidgetStyle.tint)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120, alignment: .trailing)
        }
    }
}
