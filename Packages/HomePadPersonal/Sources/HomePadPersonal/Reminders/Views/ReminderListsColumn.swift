import HomePadUI
import SwiftUI

/// Left column of the Reminders app: colored smart-list tiles, then every
/// visible list with its open count, then Add List.
struct ReminderListsColumn: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    let items: [ReminderItem]
    let selection: ReminderFilter
    let onSelect: (ReminderFilter) -> Void
    let onAddList: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                    ForEach([ReminderFilter.today, .scheduled, .all], id: \.self) { tile($0) }
                    if let list = calendar.defaultList {
                        tile(.list(list))
                    }
                }
                SectionHeader("My Lists")
                    .padding(.top, Theme.Spacing.s)
                VStack(spacing: 0) {
                    ForEach(calendar.visibleReminderLists) { list in
                        row(list)
                        Divider().padding(.leading, 64)
                    }
                    Button(action: onAddList) {
                        Label("Add List", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.m)
                    }
                    .buttonStyle(.plain)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .scrollIndicators(.hidden)
    }

    private func openCount(_ filter: ReminderFilter) -> Int {
        items.filter { !$0.isCompleted && filter.includes($0) }.count
    }

    private func tile(_ filter: ReminderFilter) -> some View {
        let isSelected = filter == selection
        let color = Color(hex: filter.colorHex)
        return Button { onSelect(filter) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Image(systemName: filter.systemImage).font(.title2)
                    Spacer()
                    Text("\(openCount(filter))").font(.display(30))
                }
                Text(filter.title).font(.headline).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.gradient.opacity(isSelected ? 1 : 0.75), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func row(_ list: CalendarSource) -> some View {
        let filter = ReminderFilter.list(list)
        let isShared = calendar.isShared(list)
        return Button { onSelect(filter) } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: filter.systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: list.colorHex), in: Circle())
                Text(list.title).font(.title3)
                if let phone = list.phone {
                    Image(systemName: "iphone").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("On \(phone.deviceName)")
                } else if !isShared {
                    Image(systemName: "person.fill").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("Personal")
                }
                Spacer()
                Text("\(openCount(filter))").font(.title3).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(filter == selection ? Color.primary.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
