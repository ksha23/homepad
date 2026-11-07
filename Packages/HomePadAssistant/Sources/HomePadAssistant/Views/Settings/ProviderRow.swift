import HomePadCore
import HomePadUI
import SwiftUI

/// One provider in the list, with a Settings-style icon tile and its status.
struct ProviderRow: View {
    let descriptor: ProviderDescriptor
    let status: ProviderStatus
    /// Rows that open a sheet show a chevron. Headers and reorderable lists do not.
    var showsChevron = true

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            SettingsIcon(systemImage: descriptor.systemImage, tint: AssistantPalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName)
                Text(descriptor.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(status.label).foregroundStyle(status.isReady ? .green : .secondary)
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
