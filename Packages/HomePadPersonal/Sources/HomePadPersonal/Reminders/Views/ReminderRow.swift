import HomePadUI
import SwiftUI

/// One reminder with a big check circle in its list color, sized for a finger
/// on a wall-mounted screen. A reminder on someone's phone whose change has not
/// reached it says so, with Try Again and Discard Change in a menu.
struct ReminderRow: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    let item: ReminderItem
    let showsList: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            row
            if let status = item.phoneStatus, status.state != .sending {
                Menu {
                    if let message = status.message { Text(message) }
                    Button("Try Again", systemImage: "arrow.clockwise") { calendar.retryPhoneChange(status.writeID) }
                    Button("Discard Change", systemImage: "trash", role: .destructive) { calendar.discardPhoneChange(status.writeID) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2)
                }
                .accessibilityLabel("Change on \(item.phoneDeviceName ?? "iPhone")")
            }
        }
    }

    private var row: some View {
        let color = Color(hex: item.colorHex)
        return Button(action: onToggle) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.largeTitle)
                    .foregroundStyle(item.isCompleted ? color : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.title2)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(item.isOverdue() ? .red : .secondary)
                    }
                    if let status = item.phoneStatus, let phone = item.phoneDeviceName {
                        PhoneChangeLabel(status: status, deviceName: phone).font(.body)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let due = item.due {
            parts.append(item.dueHasTime ? due.formatted(.relative(presentation: .named)) : due.formatted(.dateTime.weekday(.wide).month().day()))
        }
        if showsList { parts.append(item.listTitle) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}
