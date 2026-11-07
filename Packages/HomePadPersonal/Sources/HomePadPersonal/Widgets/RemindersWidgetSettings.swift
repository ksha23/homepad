import HomePadCore
import HomePadUI
import SwiftUI

/// Which list one Reminders widget shows. Each widget keeps its own
/// (`WidgetSettings`), so one can follow Groceries and another Errands.
enum RemindersWidgetSettings {
    /// The chosen list's identifier, which stays the same when the list is
    /// renamed. Nil shows the default list (Groceries out of the box), as the
    /// widget always did.
    static let list = WidgetSettingKey<String?>("list", default: nil)

    /// The list the widget shows for the person at the screen: the chosen one
    /// while they may see it, otherwise the default list. So a list only its
    /// owner may see never shows for anyone else, who sees the default list instead.
    static func shownList(_ chosen: String?, visible: [CalendarSource], defaultList: CalendarSource?) -> CalendarSource? {
        chosen.flatMap { id in visible.first { $0.id == id } } ?? defaultList
    }
}

/// The Reminders widget's Edit Widget page: every list the person at the
/// screen may see, with a check on the one the widget shows.
struct RemindersWidgetSettingsView: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Binding var settings: WidgetSettings

    var body: some View {
        let lists = calendar.visibleReminderLists
        let shown = RemindersWidgetSettings.shownList(settings[RemindersWidgetSettings.list], visible: lists,
                                                      defaultList: calendar.defaultList)
        if lists.isEmpty {
            ContentUnavailableView("No Lists", systemImage: "checklist",
                                   description: Text(calendar.hasReminderAccess ? "There are no lists you can see." : "Open Reminders to connect lists."))
        } else {
            List {
                Section {
                    ForEach(lists) { list in
                        row(list, isShown: list.id == shown?.id)
                    }
                } header: {
                    Text("List")
                } footer: {
                    Text("A list only you can see shows on this widget only while you are recognized. Anyone else sees \(calendar.defaultListName).")
                }
            }
        }
    }

    private func row(_ list: CalendarSource, isShown: Bool) -> some View {
        Button { choose(list) } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: ReminderFilter.icon(forListTitle: list.title))
                    .foregroundStyle(Color(hex: list.colorHex))
                    .frame(width: 28)
                // Color.primary, since .primary in a button is the tint.
                Text(list.title).foregroundStyle(Color.primary)
                Spacer()
                if isShown {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    /// The default list is saved as no choice, so the widget follows it if Settings names another.
    private func choose(_ list: CalendarSource) {
        settings[RemindersWidgetSettings.list] = list.id == calendar.defaultList?.id ? nil : list.id
    }
}
