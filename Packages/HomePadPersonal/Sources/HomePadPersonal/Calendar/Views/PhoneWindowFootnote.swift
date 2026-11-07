import HomePadUI
import SwiftUI

/// Says which days the person's phone sent events for, when the day, week or
/// month on screen reaches past them, so an empty stretch is not read as a free one.
struct PhoneWindowFootnote: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    let mode: CalendarDisplayMode
    let date: Date

    var body: some View {
        if let note {
            Label(note, systemImage: "iphone")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    private var note: String? {
        guard let phone = calendar.phoneSnapshot, let window = phone.window,
              calendar.shownCalendars.contains(where: { $0.phone != nil }) else { return nil }
        let shown = CalendarDateMath.interval(for: mode, around: date)
        guard shown.start < window.start || shown.end > window.end else { return nil }
        let lastDay = window.end.addingTimeInterval(-1)
        let span = (window.start..<lastDay).formatted(.interval.month(.abbreviated).day())
        return "Events from \(phone.deviceName) show for \(span)."
    }
}
