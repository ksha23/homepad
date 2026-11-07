import HomePadUI
import SwiftUI

/// The Calendars list, like Apple Calendar's: every calendar the current
/// viewer may see, grouped by account, with a checkmark to show or hide each
/// one, and Show All and Hide All. Changes apply at once to Calendar, Up Next
/// and the faces. Another member's personal calendars are not listed while
/// that member is not recognized, and who a calendar belongs to is set in
/// Settings, not here.
struct CalendarsListSheet: View {
    @Environment(HouseholdCalendarService.self) private var calendar

    var body: some View {
        let visible = calendar.visibleCalendars
        let shownCount = calendar.shownCalendars.count
        // Changes apply as they are made, so the sheet only closes.
        SheetScreen("Calendars") {
            GlassCapsuleButton("Show All", systemImage: "eye", action: calendar.showAll)
                .disabled(shownCount == visible.count)
            GlassCapsuleButton("Hide All", systemImage: "eye.slash", action: calendar.hideAll)
                .disabled(shownCount == 0)
        } content: {
            List {
                ForEach(CalendarAccountGroup.groups(visible)) { group in
                    Section(group.title) {
                        ForEach(group.calendars) { CalendarCheckRow(source: $0) }
                    }
                }
                Section {
                } footer: {
                    Text(footer)
                }
            }
        }
    }

    /// Whose choice this is, where ownership is set, and what is left out.
    private var footer: String {
        let owner = calendar.shownChoiceOwnerName.map { "These are \($0)'s choices." } ?? "These are the choices for guests, while nobody is recognized."
        var sentences = [
            "\(owner) Unchecked calendars stay out of Calendar, the Up Next widget and the faces.",
            "Who each calendar belongs to, and so who may see it, is set in Settings, under Personal Info.",
        ]
        if let phone = calendar.phoneSnapshot {
            sentences.append("Calendars from \(phone.deviceName) show only while its owner is recognized here, and are chosen in HomePad on that iPhone.")
        }
        if let note = calendar.hiddenNote(.events) { sentences.append(note) }
        return sentences.joined(separator: " ")
    }
}

/// One calendar: a check circle in its color, its name and who it belongs to.
private struct CalendarCheckRow: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    let source: CalendarSource

    var body: some View {
        let isShown = calendar.isShown(source)
        let color = Color(hex: source.colorHex)
        Button {
            calendar.setShown(!isShown, for: source)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isShown ? .white : color, color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).foregroundStyle(.primary)
                    Text(audience).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityValue(isShown ? "Shown" : "Hidden")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    /// "Shared with everyone" or "Personal to Kyle", read from Settings, or
    /// the phone it comes from.
    private var audience: String {
        if let phone = source.phone { return "On \(phone.deviceName), only while recognized" }
        let status = calendar.status(of: source)
        if status.audience == .everyone { return "Shared with everyone" }
        return "Personal to \(CalendarAudienceText.short(status.audience, names: calendar.memberNames))"
    }
}
