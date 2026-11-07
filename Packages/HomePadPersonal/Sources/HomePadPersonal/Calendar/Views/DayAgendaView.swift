import HomePadUI
import SwiftUI

/// One day: all-day pills and event cards, like HomeView's Calendar app. In
/// landscape a summary pane with a small month sits beside the list. In
/// portrait a week strip above it picks the day.
struct DayAgendaView: View {
    @Binding var selectedDate: Date
    let events: [PersonalEvent]
    let onSelect: (PersonalEvent) -> Void

    var body: some View {
        let dayEvents = events.filter { $0.overlaps(day: selectedDate) }
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height * 1.2 {
                HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                    ScrollView {
                        DaySummaryPanel(selectedDate: $selectedDate, eventCount: dayEvents.count)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: min(proxy.size.width * 0.34, 440))
                    agenda(dayEvents)
                }
            } else {
                VStack(spacing: Theme.Spacing.l) {
                    WeekStrip(selectedDate: $selectedDate)
                    agenda(dayEvents)
                }
            }
        }
    }

    @ViewBuilder
    private func agenda(_ dayEvents: [PersonalEvent]) -> some View {
        if dayEvents.isEmpty {
            EmptyStateView("Nothing Scheduled", message: "There are no events on this day in the calendars shown here.", systemImage: "sun.max")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.s) {
                    ForEach(dayEvents) { event in
                        Button { onSelect(event) } label: {
                            if event.isAllDay {
                                AllDayPill(event: event)
                            } else {
                                EventCard(event: event)
                            }
                        }
                        .buttonStyle(.pressable(scale: 0.98))
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
    }
}
