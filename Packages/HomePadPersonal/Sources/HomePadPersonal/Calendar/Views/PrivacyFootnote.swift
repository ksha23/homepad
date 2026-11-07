import HomePadUI
import SwiftUI

/// Says which calendars or lists are left out and why: personal ones wait for
/// their owner to be recognized, others were hidden in Settings.
struct PrivacyFootnote: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    let kind: CalendarSource.Kind

    var body: some View {
        if let note = calendar.hiddenNote(kind) {
            Label(note, systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Theme.Spacing.xs)
        }
    }
}
