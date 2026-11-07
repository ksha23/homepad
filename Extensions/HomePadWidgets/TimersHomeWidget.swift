import HomePadCore
import SwiftUI
import WidgetKit

/// Small Home Screen widget with the soonest kitchen timer, read from the
/// snapshot the app writes to the App Group.
struct TimersHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimerActivityAttributes.homeWidgetKind, provider: Provider()) { entry in
            TimersHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
                .widgetURL(URL(string: "homepad://app/timers"))
        }
        .configurationDisplayName("Kitchen Timers")
        .description("See your next HomePad timer at a glance.")
        .supportedFamilies([.systemSmall])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let state: TimerActivityAttributes.ContentState
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            let sample = TimerActivityAttributes.Entry(id: UUID(), label: "Pasta", duration: 600, status: .running,
                                                       endDate: Date().addingTimeInterval(420), pausedRemaining: nil)
            return Entry(date: Date(), state: .init(timers: [sample]))
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(context.isPreview ? placeholder(in: context) : current())
        }

        /// One entry now and one at each timer's end, so "Done" appears on time.
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let now = current()
            let ends = now.state.timers.compactMap(\.endDate).filter { $0 > now.date }.sorted()
            let entries = [now] + ends.map { Entry(date: $0, state: now.state) }
            completion(Timeline(entries: entries, policy: .after((ends.last ?? now.date).addingTimeInterval(3600))))
        }

        private func current() -> Entry {
            Entry(date: Date(), state: TimerActivityAttributes.loadSnapshot() ?? .init(timers: []))
        }
    }
}

struct TimersHomeWidgetView: View {
    let entry: TimersHomeWidget.Entry

    var body: some View {
        if let featured = entry.state.featured {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TimerRing(entry: featured, now: entry.date)
                        .frame(width: 34, height: 34)
                    Spacer()
                    if entry.state.timers.count > 1 {
                        Text("+\(entry.state.timers.count - 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                TimerCountdownText(entry: featured, now: entry.date)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(TimerWidgetStyle.tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(featured.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "timer")
                    .font(.title)
                    .foregroundStyle(TimerWidgetStyle.tint)
                Spacer(minLength: 0)
                Text("No Timers")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Start one on HomePad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
