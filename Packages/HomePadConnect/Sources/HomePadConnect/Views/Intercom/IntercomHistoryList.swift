import HomePadCore
import HomePadUI
import SwiftUI

/// Recent intercom messages, newest first. Tap a message to hear it again.
struct IntercomHistoryList: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent", systemImage: "clock")
            if connect.intercom.history.isEmpty {
                Text("Messages you send and receive show up here.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Spacing.m)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(connect.intercom.history) { record in
                            row(record)
                        }
                    }
                    // A new message slides in at the top.
                    .animation(Theme.Motion.standard, value: connect.intercom.history.map(\.id))
                }
            }
        }
    }

    private func row(_ record: IntercomRecord) -> some View {
        Button {
            connect.intercom.play(record)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: record.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(record.direction == .sent ? Color.accentColor : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.direction == .sent ? "To \(record.peerName)" : "From \(record.peerName)")
                        .font(.title3.weight(.semibold))
                    Text(record.text ?? "Voice message, \(Int(record.duration.rounded())) seconds")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(record.date, style: .relative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: "play.fill").foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.m)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable(scale: 0.98))
    }
}
