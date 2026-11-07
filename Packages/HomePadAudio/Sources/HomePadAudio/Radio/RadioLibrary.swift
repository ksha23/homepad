import Foundation
import HomePadCore
import Observation

/// The person's stations: the curated list, favorites, stations added by URL
/// or saved from search, recently played, and Radio Browser search.
@MainActor
@Observable
final class RadioLibrary {
    private(set) var searchResults: [RadioStation] = []
    private(set) var isSearching = false
    private(set) var searchError: String?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let client: RadioBrowserClient

    init(settings: SettingsStore, client: RadioBrowserClient = RadioBrowserClient()) {
        self.settings = settings
        self.client = client
    }

    var curated: [RadioStation] { CuratedStations.all }
    var saved: [RadioStation] { settings[AudioSettings.savedStations] }
    var recents: [RadioStation] { settings[AudioSettings.recentStations] }

    var favorites: [RadioStation] {
        settings[AudioSettings.favoriteStationIDs].compactMap(station(id:))
    }

    func station(id: String) -> RadioStation? {
        (curated + saved + recents + searchResults).first { $0.id == id }
    }

    func isFavorite(_ station: RadioStation) -> Bool {
        settings[AudioSettings.favoriteStationIDs].contains(station.id)
    }

    func toggleFavorite(_ station: RadioStation) {
        var ids = settings[AudioSettings.favoriteStationIDs]
        if let index = ids.firstIndex(of: station.id) {
            ids.remove(at: index)
        } else {
            ids.append(station.id)
            keep(station)
        }
        settings[AudioSettings.favoriteStationIDs] = ids
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        var ids = settings[AudioSettings.favoriteStationIDs]
        ids.move(fromOffsets: source, toOffset: destination)
        settings[AudioSettings.favoriteStationIDs] = ids
    }

    /// Adds a stream the person typed in and makes it a favorite.
    @discardableResult
    func addCustom(name: String, urlString: String) throws -> RadioStation {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else {
            throw AudioError.invalidStreamURL
        }
        let station = RadioStation.custom(name: name, url: url)
        toggleFavorite(station)
        return station
    }

    /// Removes a saved station everywhere.
    func remove(_ station: RadioStation) {
        settings[AudioSettings.savedStations] = saved.filter { $0.id != station.id }
        settings[AudioSettings.favoriteStationIDs] = settings[AudioSettings.favoriteStationIDs].filter { $0 != station.id }
    }

    func notePlayed(_ station: RadioStation) {
        let recents = [station] + self.recents.filter { $0.id != station.id }
        settings[AudioSettings.recentStations] = Array(recents.prefix(10))
        Task { [client] in await client.reportPlay(of: station) }
    }

    func search(_ term: String) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            searchResults = try await client.search(term)
        } catch {
            searchResults = []
            searchError = "Radio search isn't available right now."
        }
    }

    /// The best station for a spoken request: a known station first, then the directory.
    func bestStation(for query: String) async -> RadioStation? {
        if let local = Self.match(query, in: favorites + curated + saved + recents) { return local }
        let term = Self.normalize(query)
        return try? await client.search(term.isEmpty ? query : term, limit: 10).first
    }

    /// Matches a request such as "groove salad" or "jazz" against known stations
    /// by name first, then by genre tag.
    nonisolated static func match(_ query: String, in stations: [RadioStation]) -> RadioStation? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return nil }
        if let byName = stations.first(where: {
            let name = normalize($0.name)
            return name.contains(needle) || (needle.contains(name) && !name.isEmpty)
        }) {
            return byName
        }
        let words = Set(needle.split(separator: " ").map(String.init))
        return stations.first { station in station.tags.contains { words.contains($0) || needle == $0 } }
    }

    nonisolated private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "somafm", with: "")
            .replacingOccurrences(of: "radio", with: "")
            .replacingOccurrences(of: "station", with: "")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private func keep(_ station: RadioStation) {
        guard station.origin != .curated, !saved.contains(where: { $0.id == station.id }) else { return }
        settings[AudioSettings.savedStations] = saved + [station]
    }
}
