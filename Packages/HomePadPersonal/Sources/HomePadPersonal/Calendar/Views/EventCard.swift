import HomePadUI
import SwiftUI

/// A timed event: color bar, title, location and time range.
struct EventCard: View {
    let event: PersonalEvent
    var isCompact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? Theme.Spacing.xs : Theme.Spacing.m) {
            Capsule()
                .fill(Color(hex: event.colorHex))
                .frame(width: isCompact ? 4 : 6)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(event.title)
                    .font(isCompact ? .headline : .title2.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(isCompact ? 2 : 3)
                if let location = event.location, !isCompact {
                    Label(location, systemImage: "mappin.circle")
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                }
                Label(isCompact ? startTime : timeRange, systemImage: "clock")
                    .font(isCompact ? .subheadline : .tileDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(isCompact ? 1 : nil)
                    .minimumScaleFactor(0.8)
                if let status = event.phoneStatus, let phone = event.phoneDeviceName, !isCompact {
                    PhoneChangeLabel(status: status, deviceName: phone).font(.tileDetail)
                }
            }
            Spacer(minLength: 0)
            if let status = event.phoneStatus, let phone = event.phoneDeviceName, isCompact {
                PhoneChangeLabel(status: status, deviceName: phone, isCompact: true).font(.caption)
            }
            if event.isRecurring && !isCompact {
                Image(systemName: "repeat").foregroundStyle(.secondary)
            }
        }
        .padding(isCompact ? Theme.Spacing.xs : Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: event.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The title in the calendar's color, as Apple's Calendar draws it: a light
    /// tint of it on a dark page, a deep shade of it on a white one.
    private var titleColor: Color {
        let color = Color(hex: event.colorHex)
        return colorScheme == .dark ? color.mix(with: .white, by: 0.55) : color.mix(with: .black, by: 0.35)
    }

    /// A compact card sits in a week column padded by `xs`, so it is
    /// concentric with the column. A full card sits on the screen.
    private var cornerRadius: CGFloat {
        isCompact ? Theme.Radius.concentric(in: Theme.Radius.card, inset: Theme.Spacing.xs) : Theme.Radius.card
    }

    private var startTime: String {
        event.start.formatted(date: .omitted, time: .shortened)
    }

    /// Due dates (Canvas assignments, for one) start and end at the same minute,
    /// so they show one time.
    private var timeRange: String {
        guard event.end > event.start else { return startTime }
        return "\(startTime) to \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}
