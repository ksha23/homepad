import SwiftUI

/// The time in an app's header, beside the close button, as HomeView shows it
/// on nearly every app screen: on a wall display the time is what people glance
/// at most. Title-sized primary text with proportional digits, readable from
/// a few steps back (the headline-sized gray time was hard to see), redrawn
/// once a minute, the minute rolling over.
struct HeaderClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let time = context.date.clockTime()
            Text(time)
                .font(.title.weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(Theme.Motion.standard, value: time)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(context.date.formatted(date: .omitted, time: .shortened))
        }
    }
}
