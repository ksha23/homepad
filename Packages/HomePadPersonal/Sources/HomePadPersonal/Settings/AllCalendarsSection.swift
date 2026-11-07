import HomePadCore
import HomePadUI
import SwiftUI

/// Every calendar on this iPad: its account, who it belongs to and whether it
/// shows right now, so a calendar missing from HomePad can be found and fixed here.
struct AllCalendarsSection: View {
    @Environment(HouseholdCalendarService.self) private var calendar

    var body: some View {
        if calendar.hasAccess {
            let sources = calendar.allEventCalendars
            Section {
                if sources.isEmpty {
                    Text("iPadOS shares no calendars with HomePad. Add an account or a subscribed calendar in the Settings app, under Apps, Calendar, Calendar Accounts.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sources) { source in
                    CalendarStatusRow(source: source)
                }
            } header: {
                Text(calendar.isUsingDemoData ? "Demo Calendars" : "All Calendars on This iPad")
            } footer: {
                if calendar.isUsingDemoData {
                    Text("Show Demo Data is on, so demo calendars stand in for this iPad's own. Turn it off below to see the real ones.")
                } else {
                    Text("Every calendar iPadOS shares with HomePad, with its account. A calendar missing from this list is not on this iPad yet. Automatic shares holiday and Family calendars and treats the rest as Calendars Nobody Chose, so calendars added later show up without any setup.")
                }
            }
        }
    }
}

/// One calendar: its color, title and account, who sees it and why, and a menu to change that.
private struct CalendarStatusRow: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(Household.self) private var household
    let source: CalendarSource

    var body: some View {
        let status = calendar.status(of: source)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Circle()
                .fill(Color(hex: source.colorHex))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                        Text(source.accountDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    picker
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol(for: status))
                        .foregroundStyle(tint(for: status))
                        .accessibilityLabel(status.isVisibleNow ? "Showing now" : "Not showing now")
                    Text(CalendarAudienceText.explanation(for: status, unassigned: calendar.unassignedPolicy, names: calendar.memberNames))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var picker: some View {
        Picker("Belongs To", selection: choice) {
            Text("Automatic: \(short(calendar.automaticAudience(for: source)))").tag(CalendarAudienceChoice.automatic)
            Text("Everyone").tag(CalendarAudienceChoice.everyone)
            ForEach(household.members) { member in
                Text(member.name).tag(CalendarAudienceChoice.member(member.id))
            }
            if case .several(let ids) = calendar.choice(for: source) {
                Text(short(.members(ids))).tag(CalendarAudienceChoice.several(ids))
            }
            Text("Hidden").tag(CalendarAudienceChoice.hidden)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var choice: Binding<CalendarAudienceChoice> {
        Binding(get: { calendar.choice(for: source) }, set: { calendar.setChoice($0, for: source) })
    }

    private func short(_ audience: CalendarAudience) -> String {
        CalendarAudienceText.short(audience, names: calendar.memberNames)
    }

    /// An open eye when it shows right now, a lock while it waits for its owner, else a crossed eye.
    private func symbol(for status: CalendarStatus) -> String {
        if status.isVisibleNow { return "eye.fill" }
        return isAwaitingOwner(status) ? "lock.fill" : "eye.slash.fill"
    }

    private func tint(for status: CalendarStatus) -> Color {
        if status.isVisibleNow { return .green }
        return isAwaitingOwner(status) ? .orange : .red
    }

    private func isAwaitingOwner(_ status: CalendarStatus) -> Bool {
        if case .members(let owners) = status.audience {
            return owners.contains { calendar.memberNames[$0] != nil }
        }
        return false
    }
}
