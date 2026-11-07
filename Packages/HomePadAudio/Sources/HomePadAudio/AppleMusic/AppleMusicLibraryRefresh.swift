import Foundation
import HomePadCore

/// The Music library background task. Library's lists load the first time
/// they are shown and were never read again, so an album added on an iPhone
/// stayed missing until HomePad restarted. Loading every list while nobody
/// uses the screen keeps them current and opens Library at once.
@MainActor
enum AppleMusicLibraryRefresh {
    static let id = "audio.musicLibrary"
    /// A library changes by hand, a few albums at a time, so hourly is soon enough.
    static let interval: TimeInterval = 60 * 60

    static func register(in work: BackgroundWork, media: AudioMediaService) {
        work.register(BackgroundTaskDescriptor(
            id: id, title: "Apple Music Library",
            summary: "Loads the playlists, albums, artists and songs in this iPad's Apple Music library again, so music added on another device shows in Library.",
            interval: { interval }, conditions: .displayIdle
        ) { context in
            await refresh(media: media, context: context)
        })
    }

    static func refresh(media: AudioMediaService, context: BackgroundTaskContext) async -> BackgroundTaskOutcome {
        guard media.musicSource == .thisIPad else { return .skipped("Music comes from \(media.musicSource.title), not this iPad's Apple Music.") }
        guard media.demo == nil else { return .skipped("Demo music stands in for Apple Music.") }
        guard media.appleMusic.isAuthorized else { return .skipped("Media and Apple Music access has not been allowed.") }
        let library = media.appleMusicLibrary
        for kind in LibraryKind.allCases {
            guard await context.checkpoint() else { return .stopped("Someone started using the screen.") }
            await library.load(kind, force: true)
        }
        let failed = LibraryKind.allCases.filter { library.failed.contains($0) }
        if failed.count == LibraryKind.allCases.count { return .failed("Apple Music did not answer.") }
        let counts = "\(library.playlists.count) playlists, \(library.albums.count) albums, \(library.artists.count) artists, \(library.songs.count) songs."
        guard failed.isEmpty else { return .done(counts + " \(failed.map(\.title).formatted(.list(type: .and))) did not load.") }
        return .done(counts)
    }
}
