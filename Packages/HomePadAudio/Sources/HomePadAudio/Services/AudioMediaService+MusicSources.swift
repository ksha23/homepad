import Foundation
import HomePadCore

/// Checking the music sources when the Music app opens.
extension AudioMediaService {
    /// Checks every source when the Music app opens: Music Assistant in Home
    /// Assistant, Apple Music's live status and the synced library, and Spotify
    /// when it is the source. All at once, so Listen Now waits for the slowest,
    /// not their sum.
    func refreshMusicSources() async {
        if demo == nil { mediaLibrary.load() }
        async let assistant: Void = refreshMusicAssistant()
        async let appleMusic: Void = refreshAppleMusic()
        async let spotifyCheck: Void = refreshSpotifyIfSource()
        _ = await (assistant, appleMusic, spotifyCheck)
    }

    private func refreshSpotifyIfSource() async {
        if musicSource == .spotify { await refreshSpotify() }
    }

    private func refreshMusicAssistant() async {
        await musicAssistant.refreshStatusIfNeeded()
        if musicAssistant.isReady, musicAssistant.home.isEmpty { await musicAssistant.loadHome() }
    }

    private func refreshAppleMusic() async {
        guard demo == nil else { return }
        await catalog.refreshStatus()
        if catalog.status.canBrowseCatalog, catalog.recentlyPlayed.isEmpty, catalog.playlists.isEmpty {
            await catalog.loadHome()
        }
    }

    /// True once Listen Now has what it needs for the music source in use, so the
    /// page appears in one go instead of shelves arriving and changing one by one.
    var isListenNowReady: Bool {
        if musicSource == .thisIPad, let library = memberMusic.shown { return library.isHomeReady }
        if demo != nil { return true }
        switch musicSource {
        case .musicAssistant:
            switch musicAssistant.status {
            case .unknown, .checking: return false
            case .ready: return musicAssistant.hasLoadedHome
            case .notSetUp, .failed: return true
            }
        case .spotify:
            return !spotify.isReady || spotify.hasLoadedHome
        case .thisIPad:
            if catalog.status == .checking { return false }
            return !catalog.status.canBrowseCatalog || catalog.hasLoadedHome
        }
    }
}
