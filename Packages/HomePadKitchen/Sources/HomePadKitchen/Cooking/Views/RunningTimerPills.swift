import HomePadCore
import HomePadUI
import SwiftUI

/// Live countdown capsules for every active timer, shown in cooking mode's
/// header as tall as its other items (`Theme.Size.toolbarItem`). Tapping one
/// opens it full size, like HomeView's timer pill.
struct RunningTimerPills: View {
    @Environment(AppServices.self) private var services
    @State private var expandedID: HomeTimer.ID?

    private var active: [HomeTimer] {
        services.timers.timers.filter { $0.status != .finished }.sorted { $0.remaining() < $1.remaining() }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(active.prefix(3)) { timer in
                LiveTime(isActive: timer.status == .running) { now in
                    Button { expandedID = timer.id } label: {
                        Label(TimerFormat.countdown(timer.remaining(at: now)),
                              systemImage: timer.status == .paused ? "pause.fill" : "timer")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, Theme.Spacing.s)
                            .frame(minHeight: Theme.Size.toolbarItem)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("\(timer.label), \(TimerFormat.spoken(timer.remaining(at: now))) left")
                }
            }
        }
        .sheet(item: expandedBinding) { timer in
            SheetScreen(timer.label) {
                TimerFocusView(timer: timer)
                    .padding([.horizontal, .bottom], Theme.Spacing.xl)
            }
            .presentationDetents([.large])
        }
    }

    /// The expanded timer, looked up live so the sheet follows pause and +1 min.
    private var expandedBinding: Binding<HomeTimer?> {
        Binding(
            get: { services.timers.timers.first { $0.id == expandedID } },
            set: { expandedID = $0?.id }
        )
    }
}
