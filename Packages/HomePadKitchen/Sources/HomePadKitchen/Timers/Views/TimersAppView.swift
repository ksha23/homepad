import HomePadCore
import HomePadUI
import SwiftUI

/// The Timers app: a big ring for the selected timer, the list of all timers,
/// presets and a picker for a new one. From across the room only the ring shows.
/// It reopens on the timer it was showing, or the most urgent one once that
/// timer is gone.
struct TimersAppView: View {
    @Environment(AppServices.self) private var services
    @AppState(KitchenAppState.timer) private var selectedID
    @State private var isComposing = false

    private var timers: [HomeTimer] {
        services.timers.timers.sorted { lhs, rhs in
            let order: [HomeTimer.Status: Int] = [.finished: 0, .running: 1, .paused: 2]
            if lhs.status != rhs.status { return order[lhs.status, default: 3] < order[rhs.status, default: 3] }
            return lhs.remaining() < rhs.remaining()
        }
    }

    private var focused: HomeTimer? {
        timers.first { $0.id == selectedID } ?? timers.first
    }

    var body: some View {
        AppScreen("Timers", accessory: { newTimerButton }) {
            if let focused {
                ProximityAdaptive {
                    TimerFocusView(timer: focused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } near: {
                    split(focused)
                }
            } else {
                emptyLayout
            }
        }
        .sheet(isPresented: $isComposing) {
            // Full height: at the medium height the header left Start at the sheet's edge.
            SheetScreen("New Timer") {
                NewTimerComposer { isComposing = false }
                    .padding([.horizontal, .bottom], Theme.Spacing.l)
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
        .nightModeAware()
    }

    /// Only with timers running. Without any, the presets fill the screen.
    @ViewBuilder
    private var newTimerButton: some View {
        if focused != nil {
            GlassIconButton("plus", label: "New timer") { isComposing = true }
        }
    }

    /// The big ring beside the timers as tiles and the presets. Stacked in portrait.
    private func split(_ focused: HomeTimer) -> some View {
        AdaptiveStack(spacing: Theme.Spacing.xl) {
            TimerFocusView(timer: focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader("\(timers.count) \(timers.count == 1 ? "Timer" : "Timers")", systemImage: "timer")
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())],
                              spacing: Theme.Spacing.m) {
                        ForEach(timers) { timer in
                            TimerTile(timer: timer, isSelected: timer.id == focused.id) {
                                withAnimation(Theme.Motion.standard) { selectedID = timer.id }
                            }
                        }
                    }
                    // New timers fade in and finished ones fade out as the rest settle.
                    .animation(Theme.Motion.standard, value: timers.map(\.id))
                }
                .scrollIndicators(.hidden)
                SectionHeader("Presets", systemImage: "bolt.fill")
                PresetGrid(columns: 3, height: 72)
            }
            .frame(maxWidth: 600)
        }
    }

    /// No timers yet: big wheels to set one beside large presets, centered on
    /// the screen in landscape and stacked in portrait.
    private var emptyLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                composerPane.frame(width: 560)
                presetsPane.frame(width: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    composerPane
                    presetsPane
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var composerPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("New Timer", systemImage: "timer")
            NewTimerComposer(isLarge: true)
        }
    }

    private var presetsPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Presets", systemImage: "bolt.fill")
            PresetGrid(columns: 2, height: 120)
        }
    }
}
