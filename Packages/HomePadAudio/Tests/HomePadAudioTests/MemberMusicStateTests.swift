import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Each person's saved queue, place and Recently Played, as stored on the iPad.
@MainActor @Suite struct MemberMusicStateTests {
    static func point(_ title: String, song: String = "s1", position: TimeInterval = 42) -> MusicResumePoint {
        MusicResumePoint(container: .songs([song, "s2"]), songID: song, title: title, artist: "Artist", album: "Album",
                         artwork: nil, duration: 200, index: 0, position: position, savedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func ownerKeysRoundTrip() {
        let id = UUID()
        #expect(MusicQueueOwner(key: MusicQueueOwner.member(id).key) == .member(id))
        #expect(MusicQueueOwner(key: MusicQueueOwner.household.key) == .household)
        #expect(MusicQueueOwner(key: "") == nil)
        #expect(MusicQueueOwner(memberID: nil) == .household)
        #expect(MusicQueueOwner.member(id).stateKey.name == "audio.music.member.\(id.uuidString)")
    }

    @Test func recentsPutTheNewestFirstOnceAndStayWithinTheLimit() {
        var state = MemberMusicState()
        let album = RecentMusicItem(source: .appleMusic, kind: .album, itemID: "1", title: "One")
        let playlist = RecentMusicItem(source: .appleMusic, kind: .playlist, itemID: "2", title: "Two")
        state.noteRecent(album)
        state.noteRecent(playlist)
        state.noteRecent(album)
        #expect(state.recents.map(\.title) == ["One", "Two"])
        for index in 0..<40 {
            state.noteRecent(RecentMusicItem(source: .demo, kind: .album, itemID: "\(index)", title: "\(index)"))
        }
        #expect(state.recents.count == MemberMusicState.recentsLimit)
        #expect(state.recents.first?.title == "39")
    }

    @Test func recentsFromDifferentSourcesAreDifferentItems() {
        let apple = RecentMusicItem(source: .appleMusic, kind: .album, itemID: "1", title: "A")
        let spotify = RecentMusicItem(source: .spotify, kind: .album, itemID: "1", title: "A")
        #expect(apple.id != spotify.id)
    }

    @Test func survivesBeingSavedAndRead() throws {
        var state = MemberMusicState()
        state.resume = Self.point("Saved Song")
        state.upNext = [SavedQueueItem(id: "s2", title: "Next Song", subtitle: "Artist")]
        state.shuffle = true
        state.repeatMode = .one
        state.originTitle = "Night Signals"
        state.noteRecent(RecentMusicItem(source: .spotify, kind: .playlist, itemID: "spotify:playlist:x", title: "Mix",
                                         playedAt: Date(timeIntervalSince1970: 5)))
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.member.\(UUID())")!)
        let key = MusicQueueOwner.member(UUID()).stateKey
        settings[key] = state
        #expect(settings[key] == state)
    }

    /// A state saved before a field existed still loads, with the field's default.
    @Test func readsAStateWithMissingFields() throws {
        let json = #"{"shuffle": true}"#
        let state = try JSONDecoder().decode(MemberMusicState.self, from: Data(json.utf8))
        #expect(state.shuffle)
        #expect(state.repeatMode == .off)
        #expect(state.upNext.isEmpty && state.recents.isEmpty && state.resume == nil)
    }

    @Test func repeatCyclesOffAllOneOff() {
        #expect(MusicRepeatMode.off.next == .all)
        #expect(MusicRepeatMode.all.next == .one)
        #expect(MusicRepeatMode.one.next == .off)
        #expect(MusicRepeatMode.one.systemImage == "repeat.1")
    }

    @Test func savedItemsKeepTheirSongIDForUpNext() {
        let item = QueueItem(id: "entry-7", title: "Song", subtitle: "Artist", artworkURL: nil, songID: "1440")
        let saved = SavedQueueItem(item)
        #expect(saved.id == "1440")
        #expect(saved.queueItem.songID == "1440")
        #expect(saved.queueItem.title == "Song")
    }

    @Test func pageSummariesReadNaturally() {
        #expect(MusicDetail.summary(songCount: 1, duration: 200) == "1 Song, 3 Min")
        #expect(MusicDetail.summary(songCount: 12, duration: 48 * 60) == "12 Songs, 48 Min")
        #expect(MusicDetail.summary(songCount: 30, duration: 2 * 3600) == "30 Songs, 2 Hr")
        #expect(MusicDetail.summary(songCount: 30, duration: 2 * 3600 + 5 * 60) == "30 Songs, 2 Hr 5 Min")
        #expect(MusicDetail.summary(songCount: 3, duration: nil) == "3 Songs")
    }
}
