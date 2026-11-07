import HomePadCore
import HomePadUI
import SwiftUI

/// Home Screen and face widget: the recognized person's next alarm (small),
/// or as many of their next ones as fit (medium). Personal, so the shell shows
/// it only to its owner. A tap opens Alarms.
struct NextAlarmWidget: View {
    let size: WidgetSize
    @Environment(AlarmService.self) private var service
    @Environment(AppServices.self) private var services

    var body: some View {
        GlassTile {
            // "Tomorrow" turns into "Today" at midnight.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { services.events.post(.openApp(id: KitchenAlarms.appID)) }
    }

    /// The whole tile for each count, so the one that fits shows whole rows
    /// (`ViewThatFits`), like the Timers widget.
    @ViewBuilder
    private func content(now: Date) -> some View {
        let upcoming = nextRings
        if size == .small || upcoming.count <= 1 {
            layout(Array(upcoming.prefix(1)), now: now, isLarge: true)
        } else {
            ViewThatFits(in: .vertical) {
                ForEach(Array((1...min(3, upcoming.count)).reversed()), id: \.self) { count in
                    layout(Array(upcoming.prefix(count)), now: now, isLarge: count == 1)
                }
            }
        }
    }

    private func layout(_ rings: [(alarm: HomeAlarm, date: Date)], now: Date, isLarge: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Alarm", systemImage: "alarm.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            if rings.isEmpty {
                Text("No alarms").font(.title3.weight(.semibold))
            }
            ForEach(rings, id: \.alarm.id) { ring($0.alarm, at: $0.date, now: now, isLarge: isLarge) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The time big with the day and label under it for one alarm, or on one
    /// line beside the time for a list, so a medium tile holds two.
    @ViewBuilder
    private func ring(_ alarm: HomeAlarm, at date: Date, now: Date, isLarge: Bool) -> some View {
        let time = HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(AlarmFormat.clockTime(alarm)).font(.display(isLarge ? 44 : 30))
            if let period = AlarmFormat.dayPeriod(alarm) {
                Text(period).font(isLarge ? .title3.weight(.semibold) : .headline)
            }
        }
        .minimumScaleFactor(0.6)
        let detail = Text("\(Self.day(date, now: now)), \(alarm.title)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        if isLarge {
            VStack(alignment: .leading, spacing: 2) {
                time
                detail
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                time.fixedSize()
                detail
            }
        }
    }

    /// The person's alarms that are on, soonest first.
    private var nextRings: [(alarm: HomeAlarm, date: Date)] {
        guard services.household.isPersonalContentUnlocked, let owner = services.household.activeMember?.id else { return [] }
        return service.alarms(ownedBy: owner)
            .compactMap { alarm in service.upcoming[alarm.id].map { (alarm: alarm, date: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// "Today", "Tomorrow" or "Saturday".
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}
