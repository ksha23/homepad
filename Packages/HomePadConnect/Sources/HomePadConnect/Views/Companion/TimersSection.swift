import HomePadCore
import HomePadUI
import SwiftUI

/// Remote timers: what is running on HomePads, plus one-tap presets to start more.
struct TimersSection: View {
    @Environment(ConnectRuntime.self) private var connect
    let timers: [HomeTimer]
    /// The HomePad to start timers on. Nil starts them on every HomePad.
    let target: String?
    var roomOf: (HomeTimer) -> String? = { _ in nil }

    private static let presets: [(String, TimeInterval)] = [("1 min", 60), ("3 min", 180), ("5 min", 300), ("10 min", 600), ("15 min", 900), ("30 min", 1800)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Timers", systemImage: "timer")
            ForEach(timers) { timer in
                row(timer)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(Self.presets, id: \.1) { preset in
                        Button(preset.0) { start(preset.1, label: "\(preset.0) Timer") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private func row(_ timer: HomeTimer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.label).font(.headline)
                if let room = roomOf(timer) {
                    Text(room).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Group {
                if timer.status == .running, let end = timer.endDate, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                } else {
                    Text(timer.status == .finished ? "Done" : Duration.seconds(timer.remaining()).formatted(.time(pattern: .minuteSecond)))
                }
            }
            .font(.display(28).monospacedDigit())
            .foregroundStyle(.orange)
            GlassIconButton("xmark", label: "Cancel \(timer.label)", size: Theme.Size.minTapTarget) {
                Task { try? await connect.remote.send(.cancelTimer(id: timer.id), to: target) }
            }
        }
        .padding(Theme.Spacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func start(_ seconds: TimeInterval, label: String) {
        Task {
            try? await connect.remote.send(.startTimer(seconds: seconds, label: label), to: target)
            await connect.remote.refresh(target)
        }
    }
}
