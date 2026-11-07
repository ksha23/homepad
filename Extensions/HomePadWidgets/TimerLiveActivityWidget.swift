import ActivityKit
import HomePadCore
import SwiftUI
import WidgetKit

/// The kitchen timers Live Activity: the soonest timer large, up to two more
/// below, on the Lock Screen and in the Dynamic Island of the iPhone companion.
struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(TimerWidgetStyle.tint)
                .widgetURL(URL(string: "homepad://app/timers"))
        } dynamicIsland: { context in
            let featured = context.state.featured
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let featured {
                        TimerRing(entry: featured).frame(width: 40, height: 40)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let featured {
                        TimerCountdownText(entry: featured)
                            .font(.title.weight(.semibold).monospacedDigit())
                            .foregroundStyle(TimerWidgetStyle.tint)
                            .frame(maxWidth: 140, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let featured { Text(featured.label).font(.headline).lineLimit(1) }
                        ForEach(context.state.timers.dropFirst().prefix(2)) { entry in
                            TimerEntryRow(entry: entry, countdownFont: .body)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(TimerWidgetStyle.tint)
            } compactTrailing: {
                if let featured {
                    TimerCountdownText(entry: featured)
                        .monospacedDigit()
                        .foregroundStyle(TimerWidgetStyle.tint)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                if let featured {
                    TimerRing(entry: featured)
                } else {
                    Image(systemName: "timer").foregroundStyle(TimerWidgetStyle.tint)
                }
            }
            .keylineTint(TimerWidgetStyle.tint)
        }
    }
}

/// The Lock Screen banner.
struct TimerLockScreenView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let featured = state.featured {
                HStack(spacing: 14) {
                    TimerRing(entry: featured)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(featured.label)
                            .font(.headline)
                            .lineLimit(1)
                        Text(state.timers.count > 1 ? "\(state.timers.count) kitchen timers" : "Kitchen timer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    TimerCountdownText(entry: featured)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(TimerWidgetStyle.tint)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 170, alignment: .trailing)
                }
            }
            ForEach(state.timers.filter { $0.id != state.featured?.id }.prefix(2)) { entry in
                TimerEntryRow(entry: entry, countdownFont: .title3)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}
