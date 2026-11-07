import Foundation
import HomePadCore

/// Browsing Music Assistant: the Listen Now shelves and search across every provider.
extension MusicAssistantService {
    /// Loads the Listen Now shelves in parallel. Each shelf fails on its own, so one
    /// provider hiccup never blanks the screen.
    func loadHome() async {
        guard let entryID else { return }
        isLoadingHome = true
        defer { isLoadingHome = false }
        let client = self.client
        async let recent = try? client.library(entryID: entryID, mediaType: .album, orderBy: "last_played_desc", limit: 12)
        async let playlists = try? client.library(entryID: entryID, mediaType: .playlist, orderBy: "last_played_desc", limit: 20)
        async let added = try? client.library(entryID: entryID, mediaType: .album, orderBy: "timestamp_added_desc", limit: 20)
        async let artists = try? client.library(entryID: entryID, mediaType: .artist, orderBy: "last_played_desc", limit: 20)
        async let radio = try? client.library(entryID: entryID, mediaType: .radio, orderBy: "last_played_desc", limit: 20)
        async let favorites = try? client.library(entryID: entryID, mediaType: .track, favorite: true, orderBy: "timestamp_added_desc", limit: 20)
        let loaded = MusicAssistantHome(
            recentlyPlayed: await recent ?? [], playlists: await playlists ?? [], recentlyAdded: await added ?? [],
            artists: await artists ?? [], radio: await radio ?? [], favoriteTracks: await favorites ?? []
        )
        // Another member's user took over while these loaded (`use(user:)`).
        guard client.username == self.client.username else { return }
        home = loaded
        lastError = loaded.isEmpty ? "Music Assistant's library is empty or not reachable." : nil
        hasLoadedHome = true
    }

    /// Loads one kind of the Music Assistant library by name, for the Library
    /// section, the first time it is shown.
    func loadLibrary(_ type: MAMediaItem.MediaType, force: Bool = false) async {
        guard let entryID, force || library[type] == nil, !loadingLibrary.contains(type) else { return }
        loadingLibrary.insert(type)
        defer { loadingLibrary.remove(type) }
        let user = client.username
        let items = try? await client.library(entryID: entryID, mediaType: type, orderBy: "name", limit: 200)
        guard user == client.username else { return }
        library[type] = items ?? []
    }

    /// Searches every provider. An empty query clears the results.
    func search(_ query: String, mediaTypes: [MAMediaItem.MediaType]? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = trimmed
        guard !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        guard let entryID else { return }
        isSearching = true
        defer { isSearching = false }
        let user = client.username
        do {
            let results = try await client.search(entryID: entryID, query: trimmed, mediaTypes: mediaTypes, limit: 12)
            guard trimmed == searchQuery, user == client.username else { return }
            searchResults = results
            lastError = nil
        } catch {
            guard trimmed == searchQuery else { return }
            searchResults = MASearchResults()
            lastError = "Search didn't work. \(error.localizedDescription)"
        }
    }
}
