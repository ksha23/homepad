import Foundation
import Testing
@testable import HomePadAudio

/// The simulator's demo queue follows the same Up Next rules as Apple Music.
@MainActor @Suite struct DemoQueueTests {
    private func source() -> DemoPlaybackSource {
        let demo = DemoPlaybackSource(isPlaying: true)
        demo.play(DemoMusicCatalog.tracks, origin: nil)
        return demo
    }

    @Test func playNextAndPlayLaterLandInTheRightPlaces() {
        let demo = source()
        let saltwater = DemoMusicCatalog.tracksToQueue("Saltwater")
        demo.enqueue(saltwater, at: .next)
        #expect(demo.upNext.first?.title == "Saltwater")
        demo.enqueue(DemoMusicCatalog.tracksToQueue("Lanterns"), at: .later)
        #expect(demo.upNext.last?.title == "Lanterns")
        #expect(demo.nowPlaying?.title == "Golden Hour Drive")
    }

    @Test func movingRemovingAndClearingNeverTouchTheCurrentSong() async {
        let demo = source()
        let before = demo.upNext.map(\.title)
        await demo.moveUpNext(from: [0], to: 2)
        #expect(demo.upNext.map(\.title).prefix(2) == [before[1], before[0]])
        await demo.removeUpNext(at: [0])
        #expect(!demo.upNext.map(\.title).contains(before[1]))
        await demo.clearUpNext()
        #expect(demo.upNext.isEmpty)
        #expect(demo.nowPlaying?.title == "Golden Hour Drive")
    }

    @Test func aSongQueuedTwiceKeepsTwoRows() {
        let demo = source()
        let song = DemoMusicCatalog.tracks.filter { $0.title == "Undertow" }
        demo.enqueue(song, at: .next)
        demo.enqueue(song, at: .next)
        let ids = demo.upNext.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func repeatAllWrapsAndRepeatOneStays() async {
        let demo = DemoPlaybackSource(isPlaying: true)
        demo.play(Array(DemoMusicCatalog.tracks.prefix(2)), origin: "Two Songs")
        demo.setRepeat(.one)
        await demo.skipForward()
        #expect(demo.nowPlaying?.title == DemoMusicCatalog.tracks[0].title)
        demo.setRepeat(.all)
        await demo.skipForward()
        await demo.skipForward()
        #expect(demo.nowPlaying?.title == DemoMusicCatalog.tracks[0].title)
        #expect(demo.queueOrigin == "Playing from Two Songs")
    }

    @Test func shuffleKeepsEverySong() {
        let demo = source()
        let before = Set(demo.upNext.map(\.title))
        demo.setShuffle(true)
        #expect(demo.shuffle)
        #expect(Set(demo.upNext.map(\.title)) == before)
    }

    @Test func pagesFindTheirSongs() {
        #expect(DemoMusicCatalog.tracks(matching: "Night Signals").map(\.album) == ["Night Signals", "Night Signals"])
        #expect(DemoMusicCatalog.tracks(matching: "Lumen").allSatisfy { $0.artist == "Lumen" })
        #expect(DemoMusicCatalog.tracks(matching: "Undertow").first?.title == "Undertow")
    }
}
