import Foundation
import HomePadCore
import Testing
import UIKit
@testable import HomePadConnect

/// The now-playing status a HomePad pushes, and the rules for when it pushes.
@MainActor
@Suite struct RemoteMediaStatusTests {
    private let outputs = [
        AudioOutput(id: "route:living", name: "Living Room", kind: .airPlay, isActive: true),
        AudioOutput(id: "ha:media_player.kitchen", name: "Kitchen HomePod", kind: .homeAssistantPlayer, isActive: false, volume: 0.3),
    ]

    private func track(elapsed: Double?, isPlaying: Bool = true, title: String = "So What") -> RemoteMediaStatus {
        RemoteMediaStatus(track: .init(title: title, duration: 300, elapsed: elapsed, isPlaying: isPlaying, source: "appleMusic"),
                          routeName: "Living Room", outputs: [], volume: 0.5, canSeek: true)
    }

    // MARK: Encoding

    @Test func buildsFromWhatTheMediaServiceReports() throws {
        let cover = "musicKit://artwork/transient?aat=https://is1-ssl.mzstatic.com/image/thumb/abc/1200x1200bb.jpg"
        let playing = NowPlaying(title: "So What", artist: "Miles Davis", album: "Kind of Blue", artworkURL: URL(string: cover),
                                 duration: 562, elapsed: 61, isPlaying: true, source: .appleMusic, outputName: "Living Room")
        let status = RemoteMediaStatus(nowPlaying: playing, outputs: outputs, routeName: "Speakers", volume: 1.4, canSeek: true)

        let track = try #require(status.track)
        #expect(track.title == "So What")
        #expect(track.subtitle == "Miles Davis · Kind of Blue")
        #expect(track.artworkURL?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/abc/1200x1200bb.jpg")
        #expect(track.artworkKey?.count == 16)
        #expect(track.sourceKind == .appleMusic)
        #expect(status.routeName == "Living Room")
        #expect(status.volume == 1)
        #expect(status.canSeek)
        #expect(status.outputs.map(\.id) == ["route:living", "ha:media_player.kitchen"])
        #expect(status.currentOutputs.map(\.name) == ["Living Room"])
    }

    @Test func onlyTheSpeakersPlayingThisMusicAreCurrent() {
        var speakers = outputs
        speakers.append(AudioOutput(id: "ha:media_player.bedroom", name: "Bedroom", kind: .homeAssistantPlayer, isActive: true))
        // The iPad's own music: its route is current. Bedroom plays something else.
        let here = NowPlaying(title: "So What", isPlaying: true, source: .appleMusic)
        let local = RemoteMediaStatus(nowPlaying: here, outputs: speakers, routeName: "Living Room", volume: 0.5, canSeek: false)
        #expect(local.currentOutputs.map(\.id) == ["route:living"])
        #expect(local.outputs.last?.isActive == true)
        // Music on the Kitchen HomePod: only that speaker is current.
        let there = NowPlaying(title: "Undertow", isPlaying: true, source: .homeAssistant, outputName: "Kitchen HomePod")
        let remote = RemoteMediaStatus(nowPlaying: there, outputs: speakers, routeName: "iPad", volume: 0.5, canSeek: false)
        #expect(remote.currentOutputs.map(\.id) == ["ha:media_player.kitchen"])
    }

    @Test func nothingPlayingHasNoTrackVolumeOrSeek() {
        let status = RemoteMediaStatus(nowPlaying: nil, outputs: outputs, routeName: "iPad", volume: 0.6, canSeek: true)
        #expect(status.track == nil)
        #expect(status.volume == nil)
        #expect(!status.canSeek)
        #expect(status.routeName == "iPad")
    }

    @Test func liveStreamsHaveNoDurationOnTheWire() throws {
        let radio = NowPlaying(title: "KEXP", duration: .infinity, elapsed: .nan, isPlaying: true, source: .radio)
        let status = RemoteMediaStatus(nowPlaying: radio, outputs: [], routeName: "iPad", volume: 0.5, canSeek: false)
        #expect(status.track?.duration == nil)
        #expect(status.track?.elapsed == nil)
        // Infinity would make the JSON encoder throw.
        let message = try PeerMessage(type: .mediaStatus, sender: "pad", content: status)
        #expect(try MessageCodec.decode(MessageCodec.encode(message)).content(RemoteMediaStatus.self) == status)
    }

    @Test func fileCoversTravelAsAttachmentsAndNeverShowTheirPath() throws {
        let file = URL(fileURLWithPath: "/private/var/mobile/tmp/demo-artwork-42.png")
        let playing = NowPlaying(title: "Demo", artworkURL: file, isPlaying: true, source: .appleMusic)
        let status = RemoteMediaStatus(nowPlaying: playing, outputs: [], routeName: "iPad", volume: nil, canSeek: false)
        #expect(status.track?.artworkURL == nil)
        #expect(status.track?.artworkKey != nil)
        #expect(RemoteArtwork.needsAttachment(file))
        let json = String(decoding: try PeerCoding.encoder().encode(status), as: UTF8.self)
        #expect(!json.contains("demo-artwork"))
        // A cover nothing can show gets no key at all.
        #expect(RemoteArtwork.key(for: URL(string: "musicKit://artwork/library/123")) == nil)
    }

    @Test func kindsANewerHomePadAddsStillDecode() throws {
        let json: JSONValue = .object([
            "version": .number(3), "routeName": .string("Den"), "canSeek": .bool(false),
            "track": .object(["title": .string("Song"), "isPlaying": .bool(true), "source": .string("spotify")]),
            "outputs": .array([.object(["id": .string("x"), "name": .string("Den TV"), "kind": .string("chromecast"),
                                         "isActive": .bool(true), "isCurrent": .bool(true)])]),
        ])
        let status = try PeerCoding.decode(RemoteMediaStatus.self, from: json)
        #expect(status.track?.sourceKind == nil)
        #expect(status.outputs.first?.outputKind == nil)
        #expect(status.volume == nil)
    }

    // MARK: Progress and news

    @Test func progressMovesOnOnlyWhilePlaying() {
        let playing = RemoteMediaStatus.Track(title: "A", duration: 100, elapsed: 90, isPlaying: true, source: "radio")
        #expect(playing.position(after: 5) == 95)
        #expect(playing.position(after: 60) == 100)
        var paused = playing
        paused.isPlaying = false
        #expect(paused.position(after: 60) == 90)
    }

    @Test func steadyProgressIsNotNewsButAJumpIs() {
        let first = track(elapsed: 10)
        #expect(MediaStatusPublisher.isNews(first, since: nil, after: 0))
        #expect(!MediaStatusPublisher.isNews(track(elapsed: 14), since: first, after: 4))
        #expect(MediaStatusPublisher.isNews(track(elapsed: 120), since: first, after: 4))
        #expect(MediaStatusPublisher.isNews(track(elapsed: 14, title: "Freddie Freeloader"), since: first, after: 4))
        #expect(MediaStatusPublisher.isNews(track(elapsed: 14, isPlaying: false), since: first, after: 4))
        let paused = track(elapsed: 10, isPlaying: false)
        #expect(!MediaStatusPublisher.isNews(paused, since: paused, after: 30))
    }

    @Test func volumeFollowsTheSpeakerThatPlays() {
        let onKitchen = NowPlaying(title: "A", isPlaying: true, source: .homeAssistant, outputName: "Kitchen HomePod")
        #expect(MediaStatusPublisher.volume(nowPlaying: onKitchen, outputs: outputs, system: 0.9) == 0.3)
        let here = NowPlaying(title: "A", isPlaying: true, source: .radio)
        #expect(MediaStatusPublisher.volume(nowPlaying: here, outputs: outputs, system: 0.9) == 0.9)
        #expect(MediaStatusPublisher.volume(nowPlaying: nil, outputs: outputs, system: 0.9) == nil)
    }

    // MARK: Pushes

    @Test func watchingPushesTheMusicAndTheCoverOnce() async throws {
        let loop = RemoteLoop()
        let cover = try Self.writeCover()
        loop.media.nowPlaying = NowPlaying(title: "So What", artist: "Miles Davis", artworkURL: cover, duration: 562,
                                           elapsed: 61, isPlaying: true, source: .appleMusic)
        try loop.connect()

        loop.music.watch(loop.pad.id)
        await loop.settle()
        #expect(loop.server.music.watchers == [loop.phone.id])
        let first = try #require(loop.sent(.mediaStatus).first)
        #expect(first.attachment != nil)
        #expect(loop.music.status(of: loop.pad.id)?.track?.title == "So What")
        #expect(loop.music.status(of: loop.pad.id)?.volume == 0.4)
        #expect(loop.music.cover(of: loop.pad.id) != nil)

        // A change is pushed without the cover the phone already has.
        loop.media.nowPlaying?.isPlaying = false
        loop.server.music.publishIfChanged()
        await loop.settle()
        let pushes = loop.sent(.mediaStatus)
        #expect(pushes.count == 2)
        #expect(pushes.last?.attachment == nil)
        #expect(loop.music.status(of: loop.pad.id)?.track?.isPlaying == false)
        #expect(loop.music.cover(of: loop.pad.id) != nil)

        // Nothing new, nothing sent.
        loop.server.music.publishIfChanged()
        await loop.settle()
        #expect(loop.sent(.mediaStatus).count == 2)
    }

    @Test func stoppingTheWatchStopsThePushes() async throws {
        let loop = RemoteLoop()
        loop.media.nowPlaying = NowPlaying(title: "So What", isPlaying: true, source: .appleMusic)
        try loop.connect()
        loop.music.watch(loop.pad.id)
        loop.music.watch(loop.pad.id)
        await loop.settle()
        loop.music.stopWatching(loop.pad.id)
        await loop.settle()
        #expect(loop.server.music.watchers == [loop.phone.id], "another screen still watches")

        loop.music.stopWatching(loop.pad.id)
        await loop.settle()
        #expect(loop.server.music.watchers.isEmpty)
        let before = loop.sent(.mediaStatus).count
        loop.media.nowPlaying?.title = "Freddie Freeloader"
        loop.server.music.publishIfChanged()
        await loop.settle()
        #expect(loop.sent(.mediaStatus).count == before)
        #expect(loop.sent(.mediaSubscribe, toPhone: false).count == 2)
    }

    @Test func aChangeOnTheHomePadArrivesWithoutAsking() async throws {
        let loop = RemoteLoop()
        loop.media.nowPlaying = NowPlaying(title: "So What", isPlaying: true, source: .appleMusic)
        try loop.connect()
        loop.music.watch(loop.pad.id)
        await loop.settle()

        // Someone skips on the iPad. Observation notices, and the push follows.
        loop.media.nowPlaying = NowPlaying(title: "Freddie Freeloader", isPlaying: true, source: .appleMusic)
        try await Task.sleep(for: .milliseconds(400))
        await loop.settle()
        #expect(loop.music.status(of: loop.pad.id)?.track?.title == "Freddie Freeloader")
        #expect(loop.sent(.statusRequest, toPhone: false).isEmpty)
    }

    /// A 1200 pixel square PNG, like the demo covers.
    private static func writeCover() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("connect-test-cover-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1200)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
        }
        try #require(image.pngData()).write(to: url)
        return url
    }
}
