import HomePadUI
import SwiftUI

/// A compact song row: small artwork (or the track number), title, artist, an
/// optional trailing label, and a More button with Play Next and Play Later
/// when the item has a menu. Tapping the row plays it.
struct SongRow: View {
    let item: MusicTileItem
    var trailing: String?
    /// Shows this number instead of the artwork, as an album's track list does.
    var number: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: item.action) {
                HStack(spacing: Theme.Spacing.m) {
                    leading
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.tileTitle).lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.tileDetail).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    if let trailing {
                        Text(trailing).font(.tileDetail.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Image(systemName: item.isActive ? "waveform" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(item.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .symbolEffect(.variableColor.iterative, isActive: item.isActive)
                }
                .padding(.vertical, Theme.Spacing.xs)
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.title)")
            if !item.menu.isEmpty {
                MusicItemMoreButton(menu: item.menu, title: "More for \(item.title)")
            }
        }
        .musicItemContextMenu(item.menu)
        .unavailable(item.unavailableReason)
    }

    @ViewBuilder
    private var leading: some View {
        if let number {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.minTapTarget, alignment: .center)
        } else {
            item.artworkView(cornerRadius: Theme.Radius.thumbnail)
                .frame(width: 56, height: 56)
        }
    }
}

/// Songs in two columns, so a list fills a landscape screen.
struct SongGrid: View {
    let title: String
    let items: [MusicTileItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.Spacing.l)], alignment: .leading,
                          spacing: Theme.Spacing.xs) {
                    ForEach(items) { SongRow(item: $0) }
                }
            }
        }
    }
}
