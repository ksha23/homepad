import HomePadCore
import HomePadUI
import SwiftUI

/// One reminders list with tappable check circles: the list chosen in Edit
/// Widget (`RemindersWidgetSettings`), or the default list (Groceries out of
/// the box) when none is chosen or the person at the screen may not see it.
struct RemindersWidgetView: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(\.widgetSettings) private var settings
    let size: WidgetSize
    @State private var items: [ReminderItem] = []
    /// Height of one reminder row.
    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = 26

    /// The list shown, for whoever is at the screen now.
    private var list: CalendarSource? {
        RemindersWidgetSettings.shownList(settings[RemindersWidgetSettings.list], visible: calendar.visibleReminderLists,
                                          defaultList: calendar.defaultList)
    }

    var body: some View {
        let list = list
        let title = list?.title ?? calendar.defaultListName
        GlassTile(surface: .solid) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Label(title, systemImage: ReminderFilter.icon(forListTitle: title))
                        .font(.headline)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    Spacer()
                    Text("\(items.count)").font(.display(size.rows >= 2 ? 34 : 26))
                }
                if items.isEmpty {
                    Spacer(minLength: 0)
                    Text(calendar.hasReminderAccess ? "All done" : "Open Reminders to connect lists")
                        .font(.headline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    // As many reminders as fit the tile, so the tall size lists about twice as many.
                    GeometryReader { proxy in
                        let fits = max(1, Int((proxy.size.height + Theme.Spacing.xs) / (rowHeight + Theme.Spacing.xs)))
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(items.prefix(min(fits, mostRows))) { item in
                                Button {
                                    try? calendar.setCompleted(item, true)
                                } label: {
                                    HStack(spacing: Theme.Spacing.s) {
                                        Image(systemName: "circle").font(.body).foregroundStyle(.secondary)
                                        Text(item.title).font(size.rows >= 2 ? .headline : .subheadline.weight(.semibold)).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task(id: Reload(key: calendar.reloadKey, listID: list?.id)) { await reload(list) }
    }

    /// The most reminders a size lists, whatever fits.
    private var mostRows: Int { size == .tall ? 16 : 8 }

    /// What the reminders depend on: the calendars, who is looking, and the list.
    private struct Reload: Hashable {
        var key: String
        var listID: String?
    }

    private func reload(_ list: CalendarSource?) async {
        guard let list else {
            items = []
            return
        }
        items = await calendar.reminderItems(listID: list.id)
    }
}
