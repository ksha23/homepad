import HomePadUI
import SwiftUI

/// Recipe ideas from the catalog over the library, filled in the background.
/// Picks already saved are left out. While it loads the shelf shows quiet
/// placeholders, and offline it says so in one line instead of an error.
struct DiscoverShelf: View {
    let context: KitchenContext
    static let tileWidth: CGFloat = 168

    var body: some View {
        let discovery = context.discovery
        let picks = discovery.picks.filter { context.savedRecipe(for: $0) == nil }
        if picks.isEmpty, let failure = discovery.failure, !discovery.isLoading {
            offline(failure)
        } else {
            ShelfRow("Discover") {
                if picks.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in placeholder }
                } else {
                    ForEach(picks) { DiscoverTile(context: context, result: $0, width: Self.tileWidth) }
                    moreIdeas
                }
            }
        }
    }

    /// The last tile swaps the picks for new ones, like a See All at the end of a shelf.
    private var moreIdeas: some View {
        ArtworkTile(title: "More Ideas", subtitle: "From \(context.catalog.name)", width: Self.tileWidth,
                    action: { Task { await context.discovery.refresh() } }) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.primary.opacity(0.08))
                .overlay {
                    if context.discovery.isLoading {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "shuffle").font(.largeTitle).foregroundStyle(.orange)
                    }
                }
        }
        .disabled(context.discovery.isLoading)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.primary.opacity(0.08))
                .frame(width: Self.tileWidth, height: Self.tileWidth)
            Text("Recipe name").font(.headline)
            Text("Cuisine").font(.subheadline)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private func offline(_ failure: RecipeCatalogError) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Label(failure == .offline ? "Recipe ideas appear when HomePad is online." : "Recipe ideas are not available right now.",
                  systemImage: failure == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.secondary)
            GlassCapsuleButton("Try Again", systemImage: "arrow.clockwise") {
                Task { await context.discovery.refresh() }
            }
        }
    }
}
