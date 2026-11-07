import Foundation
import MusicKit

/// Covers: the real cover behind MusicKit's stand-in, and the next song's cover ahead of time.
extension AppleMusicPlayer {
    /// The cover to show for the current entry. Right after a skip MusicKit often
    /// gives the new song a stand-in cover, with one address shared by every song,
    /// and the real one a second or two later, sometimes only when asked again.
    /// Drawn, the stand-in showed black or an earlier song's cover. Instead the
    /// song's real cover comes from the catalog when MusicKit has none yet, the
    /// player is asked again until it has one, and meanwhile `CoverHold` keeps the
    /// previous cover briefly and then shows none.
    func cover(for entry: ApplicationMusicPlayer.Queue.Entry) -> Artwork? {
        let real = catalogCover(for: entry) ?? Self.realArtwork(of: entry)
        isWaitingForCover = real == nil && Self.isPlaceholder(entry.artwork)
        if isWaitingForCover {
            requestCatalogCover(for: entry)
            pollForCover()
        }
        return coverHold.update(entryID: entry.id, real: real, isLoading: isWaitingForCover, at: Date())
    }

    /// The catalog cover fetched for the entry's song, if any. Preferred over the
    /// player's own once fetched, so the cover does not swap for the same picture.
    func catalogCover(for entry: ApplicationMusicPlayer.Queue.Entry) -> Artwork? {
        guard case .song(let song) = entry.item else { return nil }
        return catalogCovers[song.id]
    }

    /// Fetches a song's cover from the Apple Music catalog. Library songs have no
    /// catalog id and get nothing, and then the player's own cover is waited for.
    func requestCatalogCover(for entry: ApplicationMusicPlayer.Queue.Entry) {
        guard case .song(let song) = entry.item, catalogCovers[song.id] == nil,
              catalogRequests.insert(song.id).inserted else { return }
        let id = song.id
        Task { [weak self] in
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
            let artwork = try? await request.response().items.first?.artwork
            guard let self else { return }
            AppleMusicTrace.note("catalog cover for \(id): \(AppleMusicTrace.name(artwork))")
            guard let artwork, !Self.isPlaceholder(artwork) else { return }
            if self.catalogCovers.count >= 40 { self.catalogCovers.removeAll() }
            self.catalogCovers[id] = artwork
            self.refresh()
        }
    }

    /// MusicKit does not always announce a song's real cover, so while the current
    /// song has only a stand-in, the player is read again a few times a second.
    private func pollForCover() {
        guard coverPollTask == nil else { return }
        coverPollTask = Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if !self.isWaitingForCover { break }
            }
            self?.coverPollTask = nil
        }
    }

    /// The entry's cover, or its song's when the entry has only MusicKit's stand-in.
    static func realArtwork(of entry: ApplicationMusicPlayer.Queue.Entry) -> Artwork? {
        let itemArtwork: Artwork? = switch entry.item {
        case .song(let song): song.artwork
        case .musicVideo(let video): video.artwork
        default: nil
        }
        return [entry.artwork, itemArtwork].compactMap { $0 }.first { !isPlaceholder($0) }
    }

    /// MusicKit's stand-in cover for an entry that is still loading.
    static func isPlaceholder(_ artwork: Artwork?) -> Bool {
        artwork?.url(width: 100, height: 100)?.pathComponents.contains("transient") == true
    }

    /// Makes the next cover's blurred backdrop ahead of time, so it is ready when
    /// the track changes.
    static func prefetch(_ artwork: Artwork?) {
        guard let url = artwork?.url(width: 1200, height: 1200) else { return }
        ArtworkWash.prepare(url)
    }
}
