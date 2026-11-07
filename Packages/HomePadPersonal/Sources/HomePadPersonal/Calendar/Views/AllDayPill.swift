import HomePadUI
import SwiftUI

/// An all-day event as a rounded pill with its date range.
struct AllDayPill: View {
    let event: PersonalEvent

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "calendar")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color(hex: event.colorHex), in: Circle())
            // Whole titles, up to three lines like Up Next and the faces, so a
            // long Canvas quiz name reads in full here too.
            Text(event.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
            if let status = event.phoneStatus, let phone = event.phoneDeviceName {
                PhoneChangeLabel(status: status, deviceName: phone, isCompact: true).font(.headline)
            }
            Spacer()
            Text(dateRange)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular.tint(Color(hex: event.colorHex).opacity(0.25)), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var dateRange: String {
        // A feed can send an all-day event that ends where it starts. Never let
        // the range run backwards, which would crash.
        let lastDay = max(event.start, Calendar.current.date(byAdding: .second, value: -1, to: event.end) ?? event.end)
        if Calendar.current.isDate(event.start, inSameDayAs: lastDay) { return "All day" }
        return (event.start..<lastDay).formatted(.interval.month(.abbreviated).day())
    }
}
