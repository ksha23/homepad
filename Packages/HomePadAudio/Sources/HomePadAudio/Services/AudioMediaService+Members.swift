import Foundation
import HomePadCore
import MusicKit

/// Each household member's own queue, place and Recently Played on this iPad.
/// Guests share the household's.
///
/// - When HomePad recognizes another person while nothing plays here, that
///   person's queue and place come back, paused. Music never starts on its own.
/// - Music that plays keeps playing for whoever started it. New music started
///   by someone else becomes their queue, and the one it replaces is saved for
///   its owner first.
/// - Only Apple Music's queue moves between people. Radio, sleep sounds and the
///   synced library stay as they are.
extension AudioMediaService {
    /// Reads whose queue the player held when HomePad last ran, with that
    /// person's saved Up Next, shuffle and repeat. Called once at launch.
    func loadQueueOwner() {
        queueOwner = MusicQueueOwner(key: services.settings[AudioSettings.musicQueueOwner]) ?? .household
        lastSeenMemberID = services.household.activeMemberID
        guard let state = services.settings[queueOwner.stateKey] else { return }
        if appleMusic.resumePoint == nil, let resume = state.resume { appleMusic.adoptResumePoint(resume) }
        appleMusic.loadSavedQueue(state)
    }

    /// Follows who uses HomePad. Called once from `start()`, then on every change.
    func trackQueueOwner() {
        let memberID = withObservationTracking {
            services.household.activeMemberID
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackQueueOwner() }
        }
        guard memberID != lastSeenMemberID else { return }
        lastSeenMemberID = memberID
        memberDidChange(to: memberID)
    }

    /// Another person uses HomePad now. Unless music plays here, their own queue
    /// and place come back, paused.
    func memberDidChange(to memberID: UUID?) {
        let owner = MusicQueueOwner(memberID: memberID)
        guard owner != queueOwner, activeSource?.isPlaying != true,
              activeKind == nil || activeKind == .appleMusic else { return }
        switchQueue(to: owner)
    }

    /// Saves the current queue for its owner and shows `owner`'s saved place, paused.
    func switchQueue(to owner: MusicQueueOwner) {
        saveOwnerState()
        setQueueOwner(owner)
        let state = services.settings[owner.stateKey] ?? MemberMusicState()
        appleMusic.holdSavedPlace(state)
        if state.resume != nil {
            activeKind = .appleMusic
            services.settings[AudioSettings.lastLocalSource] = ActiveSource.appleMusic.rawValue
        } else {
            activeKind = nil
        }
    }

    /// Before new music starts on this iPad: the queue it replaces is saved for
    /// its owner, and the new one belongs to the person using HomePad.
    func claimQueueForActiveMember() {
        let owner = activeOwner
        guard owner != queueOwner else { return }
        saveOwnerState()
        setQueueOwner(owner)
    }

    /// Saves the player's place, Up Next, shuffle and repeat for the queue's owner,
    /// when they changed. The owner's Recently Played stays as it is.
    func saveOwnerState() {
        let key = queueOwner.stateKey
        var state = services.settings[key] ?? MemberMusicState()
        let before = state
        appleMusic.savedQueue(into: &state)
        guard state != before else { return }
        services.settings[key] = state
    }

    private func setQueueOwner(_ owner: MusicQueueOwner) {
        queueOwner = owner
        services.settings[AudioSettings.musicQueueOwner] = owner.key
    }

    // MARK: Recently played

    /// The person using HomePad: a recognized member, or the household for guests.
    var activeOwner: MusicQueueOwner {
        MusicQueueOwner(memberID: services.household.activeMember?.id)
    }

    /// What the person using HomePad played here lately, newest first.
    var memberRecents: [RecentMusicItem] {
        services.settings[activeOwner.stateKey]?.recents ?? []
    }

    /// Adds what just started to the active person's Recently Played.
    func noteRecent(_ item: RecentMusicItem?) {
        guard let item else { return }
        let key = activeOwner.stateKey
        var state = services.settings[key] ?? MemberMusicState()
        state.noteRecent(item)
        services.settings[key] = state
    }
}

extension RecentMusicItem {
    /// A recently played entry for an Apple Music album, playlist, station, song or artist.
    static func appleMusic(_ item: any MusicItem) -> RecentMusicItem? {
        switch item {
        case let album as Album:
            RecentMusicItem(source: .appleMusic, kind: .album, itemID: album.id.rawValue, title: album.title,
                            subtitle: album.artistName, artwork: album.artwork)
        case let playlist as Playlist:
            RecentMusicItem(source: .appleMusic, kind: .playlist, itemID: playlist.id.rawValue, title: playlist.name,
                            subtitle: playlist.curatorName, artwork: playlist.artwork)
        case let station as Station:
            RecentMusicItem(source: .appleMusic, kind: .station, itemID: station.id.rawValue, title: station.name,
                            subtitle: "Station", artwork: station.artwork)
        case let song as Song:
            RecentMusicItem(source: .appleMusic, kind: .song, itemID: song.id.rawValue, title: song.title,
                            subtitle: song.artistName, artwork: song.artwork)
        case let artist as Artist:
            RecentMusicItem(source: .appleMusic, kind: .artist, itemID: artist.id.rawValue, title: artist.name,
                            subtitle: "Artist", artwork: artist.artwork)
        default:
            nil
        }
    }
}
