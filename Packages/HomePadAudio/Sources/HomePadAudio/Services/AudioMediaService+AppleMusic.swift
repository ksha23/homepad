import Foundation
import HomePadCore
import MusicKit

/// Playing Apple Music on this iPad: whole items, a list from a chosen song,
/// Play Next and Play Later, and adding to the library. Every new queue
/// belongs to the person using HomePad and goes in their Recently Played.
extension AudioMediaService {
    /// Starts Apple Music as the active person's queue. `start` builds and plays
    /// it, and `recent` goes in their Recently Played.
    func startAppleMusic(recent: RecentMusicItem?, _ start: () async throws -> Void) async throws {
        activate(.appleMusic)
        claimQueueForActiveMember()
        try await start()
        noteRecent(recent)
        playbackStarted()
    }

    /// Plays an Apple Music choice as the active person's queue, and adds it to
    /// their Recently Played (`recent` overrides what is noted).
    func play(_ choice: MusicChoice, recent: RecentMusicItem? = nil) async throws {
        try await startAppleMusic(recent: recent ?? choice.recent) { try await choice.play(with: appleMusic) }
    }

    /// Plays any MusicKit item from the browse screens, in order or shuffled.
    func playMusic<Item: PlayableMusicItem>(_ item: Item, shuffled: Bool = false) async {
        await perform {
            try await startAppleMusic(recent: .appleMusic(item)) { try await appleMusic.play(item, shuffled: shuffled) }
        }
    }

    /// Plays songs from a list (top songs, search results) starting at `start`,
    /// and notes `recent` as what was played.
    func playSongs(_ songs: [Song], startingAt start: Song?, shuffled: Bool = false, recent: RecentMusicItem?) async {
        await perform {
            try await startAppleMusic(recent: recent) { try await appleMusic.play(songs, startingAt: start, shuffled: shuffled) }
        }
    }

    /// Plays an album from one of its tracks, so the rest of the album follows.
    func playAlbum(_ album: Album, startingAt track: Track) async {
        await perform {
            try await startAppleMusic(recent: .appleMusic(album)) { try await appleMusic.play(album, startingAt: track) }
        }
    }

    /// Plays a playlist from one of its songs.
    func playPlaylist(_ playlist: Playlist, startingAt entry: Playlist.Entry) async {
        await perform {
            try await startAppleMusic(recent: .appleMusic(playlist)) { try await appleMusic.play(playlist, startingAt: entry) }
        }
    }

    /// Plays an Apple Music artist's top songs, as Apple Music's artist Play button does.
    func playArtist(_ artist: Artist, shuffled: Bool = false) async {
        await perform {
            let songs = try await AppleMusicPages.topSongs(of: artist)
            guard let first = songs.first else { throw AudioError.nothingFound(artist.name) }
            try await startAppleMusic(recent: .appleMusic(artist)) {
                try await appleMusic.play(songs, startingAt: shuffled ? nil : first, shuffled: shuffled)
            }
        }
    }

    /// Play Next or Play Later for Apple Music items. When Apple Music is not
    /// what this iPad plays, they start playing, as with nothing queued.
    func enqueue(appleMusic items: [any PlayableMusicItem], at position: UpNextEdit.Position,
                 recent: RecentMusicItem? = nil) async {
        await perform {
            guard activeKind == .appleMusic, canQueueAppleMusic else {
                try await startAppleMusic(recent: recent) { try await appleMusic.play(mixed: items) }
                return
            }
            try await appleMusic.enqueue(items, at: position)
        }
    }

    /// Adds a catalog song, album or playlist to the Apple Music library of the account on this iPad.
    func addToLibrary<Item: MusicLibraryAddable>(_ item: Item) async {
        await perform { try await MusicLibrary.shared.add(item) }
    }
}
