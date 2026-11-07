import HomePadCore
import HomePadUI
import SwiftUI

/// Search across the chosen source. Music Assistant searches every provider it has
/// (Apple Music, Spotify, radio, the library), with chips to narrow the kind. This
/// iPad searches the Apple Music catalog when it works, else the library and radio.
/// Spotify searches Spotify's catalog.
/// Before typing it shows recent searches and a grid of moods to start from.
struct MusicSearchView: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @State private var query = UserDefaults.standard.string(forKey: "HomePadMusicSearch") ?? ""
    @State private var filter: MAMediaItem.MediaType?

    var body: some View {
        // Built once per update. The checks below and the results view used to
        // build every tile three times.
        let results = trimmed.isEmpty ? .empty : buildResults()
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                searchField
                if media.musicSource == .musicAssistant && !trimmed.isEmpty {
                    ChoiceChips(Self.filters, selection: $filter)
                }
                if trimmed.isEmpty {
                    SearchStartView { query = $0 }
                } else if isSearching && results.isEmpty {
                    LoadingShelves(count: 2)
                } else if results.isEmpty {
                    EmptyStateView("No Results", message: "Nothing matched \"\(trimmed)\". Try an artist, a song or a mood.",
                                   systemImage: "magnifyingglass")
                } else {
                    SearchResultsView(results: results)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .task(id: "\(trimmed)|\(filter?.rawValue ?? "all")|\(media.musicSource.rawValue)") {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
            }
        }
        .font(.title2)
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: Theme.Size.tapTarget)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 760)
    }

    private var placeholder: String {
        switch media.musicSource {
        case .musicAssistant: "Artists, songs, playlists and radio in Music Assistant"
        case .spotify: "Artists, songs, albums and playlists on Spotify"
        case .thisIPad: "Artists, songs, albums and stations"
        }
    }

    private static let filters: [ChoiceChips<MAMediaItem.MediaType?>.Choice] =
        [.init(id: nil, title: "All")] + [MAMediaItem.MediaType.track, .artist, .album, .playlist, .radio].map {
            .init(id: $0, title: $0.pluralTitle, systemImage: $0.systemImage)
        }

    private var isSearching: Bool {
        switch media.musicSource {
        case .musicAssistant: media.musicAssistant.isSearching
        case .spotify: media.spotify.isSearching
        case .thisIPad: media.catalog.isLoading || media.radioLibrary.isSearching
        }
    }

    private func buildResults() -> SearchResultsModel {
        switch media.musicSource {
        case .musicAssistant:
            return media.musicAssistant.searchResults.map { SearchResultsModel(musicAssistant: $0, query: trimmed, media: media) } ?? .empty
        case .spotify:
            return media.spotify.searchResults.map { SearchResultsModel(spotify: $0, media: media) } ?? .empty
        case .thisIPad:
            return SearchResultsModel(thisIPadFor: trimmed, media: media)
        }
    }

    private func runSearch() async {
        guard !trimmed.isEmpty else { return }
        switch media.musicSource {
        case .musicAssistant:
            await media.musicAssistant.search(trimmed, mediaTypes: filter.map { [$0] })
        case .spotify:
            await media.spotify.search(trimmed)
        case .thisIPad:
            if media.catalog.status.canBrowseCatalog { await media.catalog.search(trimmed) }
            await media.radioLibrary.search(trimmed)
        }
        if !buildResults().isEmpty { rememberSearch(trimmed) }
    }

    private func rememberSearch(_ text: String) {
        var recent = services.settings[AudioSettings.recentSearches].filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        recent.insert(text, at: 0)
        services.settings[AudioSettings.recentSearches] = Array(recent.prefix(8))
    }
}

/// Before typing: recent searches and moods to start from, so the page is never empty.
private struct SearchStartView: View {
    let search: (String) -> Void
    @Environment(AppServices.self) private var services
    @Environment(AudioMediaService.self) private var media

    private static let moods: [(title: String, symbol: String)] = [
        ("Chill", "leaf.fill"), ("Focus", "brain.head.profile"), ("Dinner", "fork.knife"), ("Party", "party.popper.fill"),
        ("Workout", "figure.run"), ("Jazz", "music.quarternote.3"), ("Classical", "pianokeys"), ("Sleep", "moon.stars.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            let recent = services.settings[AudioSettings.recentSearches]
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader("Recent Searches", systemImage: "clock.arrow.circlepath")
                    SuggestionChips(recent, onTap: search)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Browse by Mood")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.l) {
                    ForEach(Self.moods, id: \.title) { mood in
                        Button { search(mood.title) } label: {
                            GeneratedArtwork(seed: mood.title, systemImage: mood.symbol)
                                .frame(height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mood.title)
                    }
                }
            }
            ForEach(MusicShelves.current(media).filter { !$0.items.isEmpty }.prefix(2)) { MusicShelf(shelf: $0) }
        }
    }
}
