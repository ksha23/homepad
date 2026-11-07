import HomePadCore
import HomePadUI
import SwiftUI

/// The Reminders app: smart lists and the household's lists on the left, the
/// chosen list on the right with big check circles and a quick add field.
///
/// It reopens on the list each person chose last. With nothing chosen, or a
/// list that is gone or not theirs to see, it opens on Today when something
/// is due, else All.
struct RemindersAppView: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @State private var items: [ReminderItem] = []
    @AppState(PersonalAppState.reminderList) private var chosen
    /// Today or All, decided once per visit when nothing chosen can show.
    @State private var visitDefault: ReminderFilter?
    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var errorMessage: String?

    var body: some View {
        AppScreen("Reminders") {
            if !calendar.hasReminderAccess && calendar.phoneReminderLists.isEmpty {
                PermissionPrompt(feature: "Reminders", systemImage: "checklist",
                                 reason: "Keep the household's grocery list and to-dos on this HomePad. Nothing leaves this iPad.",
                                 isDenied: calendar.isReminderAccessDenied) { _ = await calendar.requestReminderAccess() }
            } else if calendar.visibleReminderLists.isEmpty {
                EmptyStateView("No Lists to Show", message: "Shared lists appear for everyone. Personal lists appear once their owner is recognized.",
                               systemImage: "checklist")
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                    ReminderListsColumn(items: items, selection: currentFilter, onSelect: choose, onAddList: { isAddingList = true })
                        .frame(width: 380)
                    ReminderListDetail(filter: currentFilter, items: items.filter { currentFilter.includes($0) },
                                       onToggle: toggle, onAdd: add)
                }
                PrivacyFootnote(kind: .reminders)
            }
        }
        .task(id: calendar.reloadKey) { await reload() }
        .alert("New List", isPresented: $isAddingList) {
            TextField("Name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create", action: createList)
        }
        .alert("Reminders", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The chosen view while it can show. Otherwise All, and the first load
    /// opens Today instead when something is due or overdue (see `reload`).
    private var currentFilter: ReminderFilter {
        chosen?.filter(visibleLists: calendar.visibleReminderLists) ?? visitDefault ?? .all
    }

    private func choose(_ filter: ReminderFilter) {
        chosen = ReminderSelection(filter)
    }

    private func reload() async {
        items = await calendar.reminderItems(includeCompleted: true)
        // Decided once per visit, so checking off the last thing due today does
        // not switch the view away. Opening on the default list showed
        // Groceries every time.
        if visitDefault == nil {
            let hasDue = items.contains { !$0.isCompleted && ReminderFilter.today.includes($0) }
            visitDefault = hasDue ? .today : .all
        }
    }

    private func toggle(_ item: ReminderItem) {
        guard let index = items.firstIndex(of: item) else { return }
        withAnimation(Theme.Motion.standard) { items[index].isCompleted.toggle() }
        do {
            try calendar.setCompleted(item, !item.isCompleted)
        } catch {
            // Put the circle back, since nothing changed.
            if let again = items.firstIndex(where: { $0.id == item.id }) { items[again].isCompleted = item.isCompleted }
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let listID: String? = if case .list(let list) = currentFilter { list.id } else { nil }
        Task {
            do {
                if let listID {
                    try calendar.addReminder(title: trimmed, toListID: listID)
                } else {
                    try await calendar.addReminder(title: trimmed, due: currentFilter == .today ? Date() : nil, listName: nil)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        newListName = ""
        guard !name.isEmpty else { return }
        do {
            choose(.list(try calendar.createList(named: name)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
