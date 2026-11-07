import HomePadCore
import HomePadUI
import SwiftUI

/// Home Screen and Modular face widget: the soonest timer as a ring (small), or a
/// list of timers (medium, large). With no timers it offers presets.
struct RunningTimersWidget: View {
    let size: WidgetSize
    @Environment(AppServices.self) private var services
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition

    /// Countdowns tick only where someone can see them: not in a thumbnail,
    /// and not while the display sleeps.
    private func ticks(_ timer: HomeTimer) -> Bool {
        timer.status == .running && !isThumbnail && displayCondition != .sleeping
    }

    private var timers: [HomeTimer] {
        services.timers.timers.sorted { lhs, rhs in
            if (lhs.status == .finished) != (rhs.status == .finished) { return lhs.status == .finished }
            return lhs.remaining() < rhs.remaining()
        }
    }

    var body: some View {
        GlassTile(surface: .solid) {
            if let first = timers.first {
                switch size {
                case .small: ring(first)
                case .medium: list(limit: 2)
                case .large: list(limit: 4)
                // Not offered (`WidgetSize.standard`), but its third row would hold two more timers.
                case .tall: list(limit: 6)
                }
            } else {
                empty
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { services.events.post(.openApp(id: KitchenModule.timersAppID)) }
    }

    private func ring(_ timer: HomeTimer) -> some View {
        LiveTime(isActive: ticks(timer)) { now in
            ZStack {
                TickRing(progress: timer.progress(at: now), tickCount: 40, tickWidthRatio: 0.02)
                VStack(spacing: 2) {
                    Text(TimerFormat.countdown(timer.remaining(at: now)))
                        .font(.display(30))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text(timer.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .padding(Theme.Spacing.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// As many timers as fit, with the presets under them on the sizes two or
    /// more rows tall when there is room, so nothing runs past the tile.
    private func list(limit: Int) -> some View {
        ViewThatFits(in: .vertical) {
            // One list of distinct candidates: three lists keyed by the count
            // alone gave two views the same identity, which stops the app.
            ForEach(Self.candidates(limit: min(limit, timers.count), rows: size.rows)) { candidate in
                list(count: candidate.count, presets: candidate.presets)
            }
        }
    }

    /// One way to fill the tile: how many timers and how many presets.
    struct Candidate: Hashable, Identifiable {
        let count: Int
        let presets: Int
        var id: Self { self }
    }

    /// The ways to fill the tile, fullest first, each once.
    static func candidates(limit: Int, rows: Int) -> [Candidate] {
        let counts = Array((1...max(limit, 1)).reversed())
        let presetChoices = rows >= 2 ? [KitchenSettings.maxPresets, 3, 0] : [0]
        var seen = Set<Candidate>()
        return presetChoices.flatMap { presets in counts.map { Candidate(count: $0, presets: presets) } }
            .filter { seen.insert($0).inserted }
    }

    private func list(count: Int, presets: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            ForEach(timers.prefix(count)) { timer in
                LiveTime(isActive: ticks(timer)) { now in
                    HStack {
                        Text(timer.label).font(.title3).lineLimit(1)
                        Spacer()
                        Text(timer.statusText ?? TimerFormat.countdown(timer.remaining(at: now)))
                            .font(.display(28))
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
            if presets > 0 { PresetGrid(columns: 3, limit: presets) }
        }
    }

    /// Presets to start one: two rows when they fit, one row on a short tile.
    private var empty: some View {
        ViewThatFits(in: .vertical) {
            if size == .small {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    header
                    Spacer(minLength: 0)
                    Text("No timers").font(.title3.weight(.semibold))
                }
            } else {
                presets(KitchenSettings.maxPresets)
                presets(3)
                presets(3, height: Theme.Size.minTapTarget)
            }
            header
        }
    }

    private func presets(_ limit: Int, height: CGFloat = 56) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            PresetGrid(columns: 3, height: height, limit: limit)
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        Label("Timers", systemImage: "timer").font(.headline).foregroundStyle(.orange)
    }
}
