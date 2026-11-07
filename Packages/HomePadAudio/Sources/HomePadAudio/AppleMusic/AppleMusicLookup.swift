import Foundation
import MusicKit

/// Finds Apple Music items by ID, in the catalog or in the library of the
/// account on this iPad, for the saved place and Recently Played.
enum AppleMusicLookup {
    /// Songs by ID from the catalog, and from the library for the ones the
    /// catalog does not have (library songs, "i." IDs, after Up Next was edited).
    static func songs(_ ids: [String]) async throws -> [Song] {
        // Catalog IDs are numbers. Library IDs would make the catalog request fail.
        let catalogIDs = ids.filter { AppleMusicTiles.isCatalog(MusicItemID($0)) }
        var found: [Song] = []
        if !catalogIDs.isEmpty {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: catalogIDs.map { MusicItemID($0) })
            found = Array(try await request.response().items)
        }
        let missing = ids.filter { id in !found.contains { $0.id.rawValue == id } }
        if !missing.isEmpty {
            var library = MusicLibraryRequest<Song>()
            library.filter(matching: \.id, memberOf: missing.map { MusicItemID($0) })
            if let items = try? await library.response().items { found += items }
        }
        return found
    }

    static func station(_ id: MusicItemID, title: String) async throws -> Station {
        let request = MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: id)
        guard let station = try await request.response().items.first else { throw AudioError.nothingFound(title) }
        return station
    }

    /// An album from the catalog, or from the library (library ids start with "l.").
    static func album(_ id: MusicItemID) async throws -> Album? {
        if let album = try? await MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id).response().items.first { return album }
        var request = MusicLibraryRequest<Album>()
        request.filter(matching: \.id, equalTo: id)
        return try await request.response().items.first
    }

    /// A playlist from the library (the person's own, "p." ids) or the catalog.
    static func playlist(_ id: MusicItemID) async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: id)
        if let playlist = try? await request.response().items.first { return playlist }
        return try await MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: id).response().items.first
    }

    /// A song by ID, from the catalog or the library.
    static func song(_ id: MusicItemID) async throws -> Song? {
        try await songs([id.rawValue]).first
    }

    /// An artist by ID, from the catalog or the library.
    static func artist(_ id: MusicItemID) async throws -> Artist? {
        if let artist = try? await MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: id).response().items.first { return artist }
        var request = MusicLibraryRequest<Artist>()
        request.filter(matching: \.id, equalTo: id)
        return try await request.response().items.first
    }
}
