import HomePadCore
import HomePadUI
import SwiftUI

/// The shell's own face, used when no Faces module face is available: a huge
/// clock from across the room, plus date and weather as someone steps closer.
struct BuiltInClockFace: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        TimelineView(.everyMinute) { context in
            ZStack {
                Color.black
                VStack(spacing: Theme.Spacing.m) {
                    Text(context.date.clockTime())
                        .font(.display(260, weight: .semibold))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    ProximityAdaptive {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.glanceSubtitle)
                            .foregroundStyle(.secondary)
                    } near: {
                        VStack(spacing: Theme.Spacing.s) {
                            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.glanceSubtitle)
                                .foregroundStyle(.secondary)
                            if let weather = services.weather.current {
                                Label("\(Int(weather.temperature.rounded()))°  \(weather.conditionText)",
                                      systemImage: weather.symbolName)
                                    .font(.title2.weight(.medium))
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(Theme.Spacing.xl)
            }
            .nightModeAware()
        }
        // White on black, so glass laid over it is dark.
        .backdropTone(.black)
        .accessibilityElement(children: .combine)
    }
}
