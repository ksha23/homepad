import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Music commands from the phone, through the HomePad's server and back.
@MainActor
@Suite struct RemoteMusicCommandTests {
    /// `RemoteCommand` as HomePads before music control decode it.
    private enum LegacyRemoteCommand: Codable {
        case showFace(id: String)
        case openApp(id: String)
        case goAmbient
        case startTimer(seconds: Double, label: String)
        case cancelTimer(id: UUID)
        case ask(prompt: String)
        case runScene(id: String)
    }

    // MARK: Wire format

    @Test func mediaCommandsRoundTripThroughMessages() throws {
        let commands: [MediaCommand] = [
            .play, .pause, .nextTrack, .previousTrack, .seek(seconds: 42.5), .setVolume(level: 0.35),
            .selectOutput(id: "ha:media_player.kitchen"), .playSearch(query: "Kind of Blue"),
        ]
        for media in commands {
            let message = try PeerMessage(type: .command, sender: "phone", content: RemoteCommand.media(command: media))
            let decoded = try MessageCodec.decode(MessageCodec.encode(message))
            #expect(try decoded.content(RemoteCommand.self) == .media(command: media))
        }
    }

    @Test func mediaCommandsHaveAStableShapeOnTheWire() throws {
        let json = try PeerCoding.jsonValue(from: RemoteCommand.media(command: .seek(seconds: 30)))
        #expect(json == .object(["media": .object(["command": .object(["seek": .object(["seconds": .number(30)])])])]))
    }

    @Test func olderHomePadsCannotReadMusicCommands() throws {
        let music = try PeerCoding.jsonValue(from: RemoteCommand.media(command: .pause))
        #expect(throws: (any Error).self) { try PeerCoding.decode(LegacyRemoteCommand.self, from: music) }
        // Older commands still read the same, so old HomePads keep working.
        let face = try PeerCoding.jsonValue(from: RemoteCommand.showFace(id: "faces.photos"))
        #expect(throws: Never.self) { try PeerCoding.decode(LegacyRemoteCommand.self, from: face) }
    }

    @Test func statusFromAnOlderHomePadSpeaksTheBaseVersion() throws {
        // What a HomePad from before music control sends: no remoteVersion.
        let old: JSONValue = .object([
            "deviceID": .string("pad"), "name": .string("Kitchen"), "faces": .array([]), "apps": .array([]),
            "timers": .array([]), "scenes": .array([]), "nowPlaying": .string("So What, Miles Davis"),
            "updatedAt": .number(1_800_000_000),
        ])
        let status = try PeerCoding.decode(HomePadStatus.self, from: old)
        #expect(status.remoteVersion == nil)
        #expect(status.speaksVersion == RemoteProtocol.base)
        #expect(!status.supportsMusic)
        #expect(!status.understands(.media(command: .play)))
        #expect(status.understands(.ask(prompt: "Play jazz")))
    }

    @Test func replyOutcomesANewerHomePadAddsReadAsFailed() throws {
        let id = UUID()
        let json: JSONValue = .object(["commandID": .string(id.uuidString), "outcome": .string("queued"), "message": .string("Later.")])
        let reply = try PeerCoding.decode(CommandReply.self, from: json)
        #expect(reply == CommandReply(commandID: id, outcome: .failed, message: "Later."))
    }

    // MARK: Phone to HomePad and back

    @Test func searchPlaysOnTheHomePadAndSaysWhat() async throws {
        let loop = RemoteLoop()
        try loop.connect()
        let text = try await loop.music.send(.playSearch(query: "  blue in green \n"), to: loop.pad.id)
        #expect(text == "Playing Blue in Green.")
        #expect(loop.media.calls == ["search blue in green"])
        // Every answer comes with fresh status.
        let reply = try #require(loop.sent(.commandReply).first).content(CommandReply.self)
        #expect(reply.outcome == .done)
        #expect(try loop.sent(.status).last?.content(HomePadStatus.self).remoteVersion == RemoteProtocol.current)
    }

    @Test func transportAndVolumeRunThroughTheMediaService() async throws {
        let loop = RemoteLoop()
        try loop.connect()
        for command: MediaCommand in [.play, .pause, .nextTrack, .previousTrack, .setVolume(level: 1.7), .setVolume(level: -2),
                                      .selectOutput(id: "ha:media_player.kitchen"), .seek(seconds: 42)] {
            try await loop.music.send(command, to: loop.pad.id)
        }
        #expect(loop.media.calls == ["play", "pause", "next", "previous", "volume 1.0", "volume 0.0",
                                     "select ha:media_player.kitchen", "seek 42.0"])
    }

    @Test func valuesFromThePhoneAreCheckedFirst() async throws {
        let loop = RemoteLoop()
        try loop.connect()
        let rejected: [(MediaCommand, RemoteCommandError)] = [
            (.seek(seconds: -1), .badNumber),
            (.playSearch(query: "   "), .emptySearch),
            (.playSearch(query: String(repeating: "a", count: MediaCommand.maxQueryLength + 1)), .searchTooLong),
            (.selectOutput(id: "route:gone"), .unknownSpeaker),
        ]
        for (command, error) in rejected {
            await #expect(throws: RemoteError.failed(error.errorDescription!)) {
                try await loop.music.send(command, to: loop.pad.id)
            }
        }
        #expect(loop.media.calls.isEmpty)
    }

    @Test func numbersJSONCannotCarryAreRefusedToo() async throws {
        // A phone cannot even encode these, but the HomePad checks anyway.
        let loop = RemoteLoop()
        let executor = CommandExecutor(services: loop.padServices)
        for command: MediaCommand in [.setVolume(level: .nan), .seek(seconds: .infinity), .seek(seconds: .nan)] {
            await #expect(throws: RemoteCommandError.badNumber) { try await executor.execute(.media(command: command)) }
        }
        #expect(loop.media.calls.isEmpty)
    }

    @Test func seekNeedsSomethingThatCanSeek() async throws {
        let loop = RemoteLoop()
        loop.media.canSeek = false
        try loop.connect()
        await #expect(throws: RemoteError.failed(RemoteCommandError.cannotSeek.errorDescription!)) {
            try await loop.music.send(.seek(seconds: 10), to: loop.pad.id)
        }
        #expect(loop.media.calls.isEmpty)
    }

    @Test func searchErrorsReachThePhone() async throws {
        struct NothingFound: LocalizedError { var errorDescription: String? { "Nothing found for zzz." } }
        let loop = RemoteLoop()
        loop.media.searchError = NothingFound()
        try loop.connect()
        await #expect(throws: RemoteError.failed("Nothing found for zzz.")) {
            try await loop.music.send(.playSearch(query: "zzz"), to: loop.pad.id)
        }
    }

    // MARK: Versions

    @Test func anOlderHomePadIsToldToUpdateWithoutSendingAnything() async throws {
        let loop = RemoteLoop()
        try loop.connect(remoteVersion: nil)
        await #expect(throws: RemoteError.updateRequired(homePad: "Kitchen")) {
            try await loop.music.send(.play, to: loop.pad.id)
        }
        #expect(loop.sent(.command, toPhone: false).isEmpty)
        #expect(RemoteError.updateRequired(homePad: "Kitchen").errorDescription == "Update HomePad on Kitchen to use this from here.")
    }

    @Test func aCommandTooNewForTheHomePadGetsUnsupported() async throws {
        let loop = RemoteLoop()
        let future = PeerMessage(type: .command, sender: "phone", body: .object(["hologram": .object(["room": .string("Den")])]))
        let replies = await loop.server.handle(command: future, from: loop.phone)
        #expect(replies.map(\.type) == [.commandReply, .status])
        let reply = try replies[0].content(CommandReply.self)
        #expect(reply.commandID == future.id)
        #expect(reply.outcome == .unsupported)
        #expect(reply.message?.hasPrefix("Update HomePad on") == true)
    }

    @Test func noStatusYetMeansUnavailable() async {
        let loop = RemoteLoop()
        await #expect(throws: PeerLinkError.self) { try await loop.music.send(.play, to: loop.pad.id) }
    }

    // MARK: Replies

    @Test func onlyTheHomePadAskedCanAnswer() async throws {
        let loop = RemoteLoop()
        try loop.connect()
        var sent: PeerMessage?
        loop.remote.transmit = { message, _ in sent = message }
        let answer = Task { try await loop.remote.perform(.media(command: .play), on: loop.pad.id) }
        for _ in 0..<20 where sent == nil { await Task.yield() }
        let id = try #require(sent?.id)

        loop.remote.finish(id, from: "pad-impostor", with: .success(CommandReply(commandID: id, outcome: .done, message: "Fake")))
        loop.remote.finish(id, from: loop.pad.id, with: .success(CommandReply(commandID: id, outcome: .done, message: "Real")))
        #expect(try await answer.value == "Real")
    }

    @Test func aHomePadThatNeverAnswersTimesOut() async throws {
        let loop = RemoteLoop()
        try loop.connect()
        loop.remote.transmit = { _, _ in }
        await #expect(throws: PeerLinkError.timedOut) {
            try await loop.remote.perform(.media(command: .play), on: loop.pad.id, timeout: .milliseconds(50))
        }
    }
}
