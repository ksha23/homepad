import EventKit
import HomePadCore
import HomePadUI
import SwiftUI

/// Who each calendar (or reminders list) belongs to. One row for everyone and
/// one per member. Tapping a row opens Apple's calendar chooser.
struct CalendarMappingSection: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(Household.self) private var household
    let kind: CalendarSource.Kind

    @State private var editing: CalendarAudienceTarget?

    var body: some View {
        Section {
            if hasAccess {
                row(.everyone, title: "Shared with Everyone", member: nil)
                ForEach(household.members) { member in
                    row(.member(member.id), title: member.name, member: member)
                }
                if kind == .events {
                    @Bindable var calendar = calendar
                    Picker("Calendars Nobody Chose", selection: $calendar.unassignedPolicy) {
                        ForEach(UnassignedCalendarPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } else if kind == .events {
                // Once someone said no, only the Settings app can grant access, so a
                // plain "Allow" button would do nothing. The prompt says where to go.
                CalendarAccessPrompt(style: .row)
            } else {
                PermissionPrompt(feature: "Reminders", systemImage: "checklist",
                                 reason: "See the household's lists and add items by touch or voice.",
                                 isDenied: calendar.isReminderAccessDenied, style: .row) { _ = await calendar.requestReminderAccess() }
            }
        } header: {
            Text(kind == .events ? "Calendars" : "Reminders Lists")
        } footer: {
            Text(kind == .events
                 ? "This iPad is signed in to one Apple Account. Family members share their calendars with that account from their iPhone, then you choose here who each one belongs to. Personal calendars show only while their owner is recognized."
                 : "Shared lists, like Groceries, show for everyone. Personal lists show only while their owner is recognized.")
        }
    }

    private var hasAccess: Bool {
        kind == .events ? calendar.hasAccess : calendar.hasReminderAccess
    }

    private func row(_ target: CalendarAudienceTarget, title: String, member: HouseholdMember?) -> some View {
        let titles = calendar.titles(for: target, kind: kind)
        return Button {
            editing = target
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                if let member {
                    AvatarView(member: member, size: 36)
                } else {
                    Image(systemName: "person.3.fill").frame(width: 36, height: 36).foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(titles.isEmpty ? "None" : titles.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        // Each row presents its own chooser. A section hands its modifiers
        // to every row, and several sheets on one binding present none.
        .sheet(item: Binding(get: { editing?.id == target.id ? editing : nil }, set: { editing = $0 })) {
            chooser(for: $0)
        }
    }

    @ViewBuilder
    private func chooser(for target: CalendarAudienceTarget) -> some View {
        let selected = calendar.selection(for: target, kind: kind)
        let finish: (Set<String>?) -> Void = { ids in
            if let ids { calendar.applySelection(ids, for: target, kind: kind) }
            editing = nil
        }
        if let backend = calendar.eventKitBackend {
            CalendarChooserSheet(store: backend.eventStore, entityType: kind == .events ? .event : .reminder,
                                 title: chooserTitle(target), selectedIDs: selected, onFinish: finish)
                .systemSheetStyle()
        } else {
            DemoCalendarChooser(title: chooserTitle(target), sources: calendar.allSources(kind), selectedIDs: selected, onFinish: finish)
        }
    }

    private func chooserTitle(_ target: CalendarAudienceTarget) -> String {
        switch target {
        case .everyone: "Shared with Everyone"
        case .member(let id): household.members.first { $0.id == id }.map { "\($0.name)'s" } ?? "Personal"
        }
    }
}

extension CalendarAudienceTarget: Identifiable {
    public var id: String {
        switch self {
        case .everyone: "everyone"
        case .member(let id): id.uuidString
        }
    }
}
