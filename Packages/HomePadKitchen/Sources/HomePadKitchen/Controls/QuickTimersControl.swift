import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center tile (2x2): the next timer's countdown and four quick timers.
struct QuickTimersControl: View {
    @Environment(AppServices.self) private var services
    @Environment(\.isThumbnail) private var isThumbnail

    private var next: HomeTimer? {
        services.timers.timers.filter { $0.status == .running }.min { $0.remaining() < $1.remaining() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label("Timers", systemImage: "timer").font(.headline)
                Spacer()
                if let next {
                    LiveTime(isActive: !isThumbnail) { now in
                        Text(TimerFormat.countdown(next.remaining(at: now)))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { services.events.post(.openApp(id: KitchenModule.timersAppID)) }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible(), spacing: Theme.Spacing.s)],
                      spacing: Theme.Spacing.s) {
                ForEach(services.settings[KitchenSettings.presets].prefix(4)) { preset in
                    Button {
                        services.timers.start(duration: preset.seconds, label: preset.title)
                    } label: {
                        Text(preset.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassCapsule(size: .regular))
                    .accessibilityLabel("Start a \(preset.title) timer")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
    }
}
