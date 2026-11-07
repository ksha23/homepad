import HomePadUI
import SwiftUI

/// The chosen list: a quick add field, open reminders with big check circles,
/// and completed ones behind a toggle.
struct ReminderListDetail: View {
    let filter: ReminderFilter
    let items: [ReminderItem]
    let onToggle: (ReminderItem) -> Void
    let onAdd: (String) -> Void

    @State private var draft = ""
    @State private var showsCompleted = false
    @FocusState private var isAdding: Bool

    var body: some View {
        let color = Color(hex: filter.colorHex)
        let open = items.filter { !$0.isCompleted }
        let done = items.filter(\.isCompleted)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(filter.title).font(.display(44, weight: .bold)).foregroundStyle(color)
                Spacer()
                Text("\(open.count)").font(.display(44)).foregroundStyle(color)
            }
            addField(color: color)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(open) { item in
                        ReminderRow(item: item, showsList: filter.showsListName) { onToggle(item) }
                        Divider().padding(.leading, 72)
                    }
                    if open.isEmpty {
                        Text(filter == .today ? "Nothing due today." : "All done.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.Spacing.l)
                    }
                    if !done.isEmpty {
                        Button {
                            withAnimation(Theme.Motion.standard) { showsCompleted.toggle() }
                        } label: {
                            Label(showsCompleted ? "Hide Completed" : "Show Completed (\(done.count))",
                                  systemImage: showsCompleted ? "chevron.up" : "chevron.down")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Theme.Spacing.m)
                        }
                        .buttonStyle(.plain)
                        if showsCompleted {
                            ForEach(done) { item in
                                ReminderRow(item: item, showsList: filter.showsListName) { onToggle(item) }
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addField(color: Color) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(color)
            TextField("New Reminder", text: $draft)
                .font(.title3)
                .focused($isAdding)
                .submitLabel(.done)
                .onSubmit {
                    onAdd(draft)
                    draft = ""
                    isAdding = true
                }
        }
        .padding(Theme.Spacing.m)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
