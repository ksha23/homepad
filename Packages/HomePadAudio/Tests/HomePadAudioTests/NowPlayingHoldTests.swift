import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Now Playing must not flicker while a track changes.
@Suite struct NowPlayingHoldTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)
    private let first = NowPlaying(title: "Anti-Hero", artist: "Taylor Swift", album: "Midnights",
                                   artworkURL: URL(string: "https://example.com/a.jpg"), duration: 200, isPlaying: true)
    private let second = NowPlaying(title: "Lavender Haze", artist: "Taylor Swift", duration: 202, isPlaying: true)

    @Test func briefGapKeepsTheLastItem() {
        var hold = NowPlayingHold(window: 1.25)
        hold.observe(first, at: start)
        #expect(hold.resolve(nil, at: start) == first, "before the gap is observed")
        hold.observe(nil, at: start.addingTimeInterval(0.1))
        #expect(hold.resolve(nil, at: start.addingTimeInterval(1.0)) == first)
        #expect(hold.resolve(nil, at: start.addingTimeInterval(1.4)) == nil, "a real stop clears after the window")
        #expect(hold.expiry(after: start.addingTimeInterval(0.2)) == start.addingTimeInterval(1.25), "the first track's change ends first")
        #expect(hold.expiry(after: start.addingTimeInterval(1.3)) == start.addingTimeInterval(1.35))
    }

    @Test func pausedReportDuringASkipStillShowsPlaying() {
        var hold = NowPlayingHold(window: 1.25)
        hold.observe(first, at: start)
        var loading = second
        loading.isPlaying = false
        #expect(hold.resolve(loading, at: start.addingTimeInterval(0.2))?.isPlaying == true, "seen before observe")
        hold.observe(loading, at: start.addingTimeInterval(0.2))
        #expect(hold.resolve(loading, at: start.addingTimeInterval(1.0))?.isPlaying == true)
        #expect(hold.resolve(loading, at: start.addingTimeInterval(1.6))?.isPlaying == false, "a real pause shows after the window")
    }

    @Test func sameTrackKeepsArtworkAndDuration() {
        var hold = NowPlayingHold()
        hold.observe(first, at: start)
        var partial = first
        partial.artworkURL = nil
        partial.duration = nil
        partial.album = nil
        let shown = hold.resolve(partial, at: start.addingTimeInterval(0.5))
        #expect(shown?.artworkURL == first.artworkURL)
        #expect(shown?.duration == 200)
        #expect(shown?.album == "Midnights")
    }

    @Test func newTrackReplacesTheOldOneAtOnce() {
        var hold = NowPlayingHold()
        hold.observe(first, at: start)
        let shown = hold.resolve(second, at: start.addingTimeInterval(0.1))
        #expect(shown?.title == "Lavender Haze")
        #expect(shown?.artworkURL == nil, "artwork from another track never carries over")
    }

    @Test func pausingTheSameTrackShowsAtOnce() {
        var hold = NowPlayingHold()
        hold.observe(first, at: start)
        var paused = first
        paused.isPlaying = false
        #expect(hold.resolve(paused, at: start.addingTimeInterval(5))?.isPlaying == false)
    }
}

/// "Play Taylor Swift in the kitchen" splits into what and where.
@Suite struct SpokenMusicRequestTests {
    private let speakers = [
        AudioOutput(id: "ha:media_player.kitchen", name: "Kitchen", kind: .homeAssistantPlayer),
        AudioOutput(id: "ha:media_player.living_room", name: "Living Room HomePods", kind: .homeAssistantPlayer),
    ]

    @Test func findsTheSpeakerAtTheEnd() {
        #expect(SpokenMusicRequest("Taylor Swift in the kitchen", speakers: speakers)
                == SpokenMusicRequest(query: "Taylor Swift", speakerID: "ha:media_player.kitchen"))
        #expect(SpokenMusicRequest("jazz on the living room HomePods", speakers: speakers).speakerID == "ha:media_player.living_room")
    }

    @Test func leavesTitlesAlone() {
        #expect(SpokenMusicRequest("Born on the Bayou", speakers: speakers).query == "Born on the Bayou")
        #expect(SpokenMusicRequest("Songs in the Key of Life", speakers: speakers).speakerID == nil)
        #expect(SpokenMusicRequest("in the kitchen", speakers: speakers).speakerID == nil, "nothing left to play")
    }
}

extension SpokenMusicRequest {
    init(query: String, speakerID: String?) {
        self.init(query, speakers: [])
        self.query = query
        self.speakerID = speakerID
    }
}
