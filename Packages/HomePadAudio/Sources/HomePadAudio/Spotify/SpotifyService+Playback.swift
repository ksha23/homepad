import Foundation
import HomePadCore

/// What Spotify plays, where, and its controls, through the Web API's player
/// endpoints (https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback).
/// They work only for Premium accounts, and only while a Connect device is on.
extension SpotifyService {
    /// Now Playing for every surface, with the position moved on since the last reading.
    var nowPlaying: NowPlaying? { playback?.nowPlaying() }

    /// Where new music goes for the account in use (`SpotifyTarget`).
    var target: SpotifyTarget {
        SpotifyTarget.choose(chosen: currentRecord?.deviceID ?? "", devices: devices, playing: playback?.device,
                             thisIPadIsOthers: thisIPadIsOthers)
    }

    /// True when new music plays on this iPad's Spotify app, the default. Its
    /// sound follows the iPad's AirPlay, which is how it reaches HomePods.
    var targetsThisIPad: Bool { target == .thisIPad }

    /// The Connect device ID of the Spotify app on this iPad under the account in use, once learned.
    var thisIPadID: String? {
        get { currentRecord?.thisIPadID }
        set {
            guard let owner else { return }
            accounts.update(owner) { $0.thisIPadID = newValue }
        }
    }

    /// The Spotify app on this iPad while it is a Connect device: open, playing,
    /// or paused a short while. iPadOS suspends it some time after it stops, and
    /// it then leaves the list.
    var thisIPad: SpotifyDevice? {
        thisIPadID.flatMap { id in devices.first { $0.id == id } }
    }

    /// Whose Spotify the Spotify app on this iPad is signed in to, by name,
    /// when it is not the account in use: a member's name when they linked
    /// that account here, else Spotify's name for it. Nil while it is the same
    /// Spotify user, or HomePad has not seen it yet.
    var thisIPadIsOthers: String? {
        guard let other = SpotifyAccountChoice.otherAccount(onThisIPad: accounts.thisIPadUser, inUse: currentRecord?.user) else {
            return nil
        }
        if let id = accounts.owner(of: other)?.memberID, let name = memberName(id) { return name }
        return other.name ?? "another account"
    }

    /// True when what Spotify plays, or will play next, comes out of this iPad,
    /// so the iPad's AirPlay picks the speakers and sets their volume.
    var playsHere: Bool {
        if playback?.item != nil, let device = playback?.device { return device.id == thisIPadID }
        return targetsThisIPad
    }

    /// The device new music plays on: this iPad's Spotify app, the device
    /// chosen in the Music app if it is on, else the active one.
    var targetDevice: SpotifyDevice? {
        switch target {
        case .thisIPad: thisIPad
        case .device(let device): device
        case .thisIPadIsOthers, .noDevice: nil
        }
    }

    // MARK: Reading

    /// Reads what the account in use plays. Once its music stops, the account
    /// of whoever HomePad recognizes now takes over.
    func refreshPlayback() async {
        guard hasSignIn else { return }
        let epoch = accountEpoch
        do {
            let json = try await client.get("me/player")
            guard isCurrent(epoch) else { return }
            playback = SpotifyPlayback(json: json)
            if playback?.isPlaying == true {
                lastPlayingAt = Date()
                if playback?.device?.id == thisIPadID { lastPlayingHereAt = Date() }
            }
            learnThisIPad()
            clearTransientProblem()
            followRecognizedMember()
        } catch {
            if isCurrent(epoch) { note(error) }
        }
    }

    func refreshDevices() async {
        guard hasSignIn else { return }
        let epoch = accountEpoch
        do {
            let list = SpotifyDevice.list(try await client.get("me/player/devices"))
            guard isCurrent(epoch) else { return }
            devices = list
            hasReadDevices = true
            learnThisIPad()
            clearTransientProblem()
        } catch {
            if isCurrent(epoch) { note(error) }
        }
    }

    // MARK: This iPad

    /// Learns which device is this iPad's Spotify app from what HomePad sees now.
    func learnThisIPad() {
        let playing = playback?.isPlaying == true ? playback?.device : nil
        let learned = SpotifyThisIPad.identify(.init(
            devices: devices, remembered: thisIPadID, playing: playing,
            otherAppPlaysHere: otherAppPlaysHere(), homePadPlays: homePadPlays(), listedBeforeWake: wakeBaseline
        ))
        if learned != thisIPadID {
            thisIPadID = learned
            trace.log("spotify here: learned this iPad's device")
        }
        // Listed under this account: the Spotify app here is signed in as this user.
        if thisIPad != nil, let user = currentRecord?.user { accounts.noteThisIPad(user) }
        traceListing()
    }

    /// HomePad is about to open Spotify here: what is listed now tells the new device apart.
    func beginWake() {
        wakeBaseline = Set(devices.map(\.id))
    }

    func endWake() {
        wakeBaseline = nil
    }

    /// Notes in the audio trace when the Spotify app here joins or leaves
    /// Connect, and how long after it last played. That is how long HomePad
    /// can start Spotify here without opening the app, measured on the iPad.
    private func traceListing() {
        let isListed = thisIPad != nil
        guard isListed != wasListedHere else { return }
        wasListedHere = isListed
        guard !isListed else { return trace.log("spotify here: in the device list") }
        let idle = lastPlayingHereAt.map { ", \(Int(Date().timeIntervalSince($0))) s after it last played here" } ?? ""
        trace.log("spotify here: left the device list\(idle)")
    }

    /// Up Next from Spotify's queue (read only: the Web API can add to it, not reorder it).
    func refreshQueue() async {
        let epoch = accountEpoch
        guard hasSignIn, let json = try? await client.get("me/player/queue"), isCurrent(epoch) else { return }
        upNext = SpotifyItem.list(json["queue"])
    }

    // MARK: Polling

    /// A Spotify screen is showing: read what plays every few seconds.
    func watch() {
        watchers += 1
        startPolling()
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
    }

    /// Reads what plays now and then while it matters (`pollInterval`). Ends by itself.
    func startPolling() {
        guard pollTask == nil, pollInterval() != nil else { return }
        let id = UUID()
        pollID = id
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.pollOnce() else { break }
                try? await Task.sleep(for: .seconds(interval))
            }
            if self?.pollID == id { self?.pollTask = nil }
        }
    }

    private func pollOnce() async -> TimeInterval? {
        guard pollInterval() != nil else { return nil }
        await refreshPlayback()
        // The device list shows whether the Spotify app here is still awake.
        if targetsThisIPad { await refreshDevices() }
        return pollInterval()
    }

    /// Every 3 seconds while a Spotify screen shows, every 15 while music plays,
    /// every 30 for ten minutes after it stops, then not at all. Never while
    /// Spotify is not the music source, so an always-on iPad does not ask all day.
    func pollInterval(now: Date = Date()) -> TimeInterval? {
        Self.pollInterval(isActive: hasSignIn && isEnabled && isSelected(), watchers: watchers,
                          isPlaying: playback?.isPlaying == true, lastPlayingAt: lastPlayingAt, now: now)
    }

    nonisolated static func pollInterval(isActive: Bool, watchers: Int, isPlaying: Bool, lastPlayingAt: Date?,
                                         now: Date) -> TimeInterval? {
        guard isActive else { return nil }
        if watchers > 0 { return 3 }
        if isPlaying { return 15 }
        if let lastPlayingAt, now.timeIntervalSince(lastPlayingAt) < 600 { return 30 }
        return nil
    }

    // MARK: Playing

    /// Plays a track, album, playlist or artist by URI on the target device. In
    /// an album or playlist (`context`), `uri` is the track to start at. With
    /// this iPad as the target, Spotify must be open here (`SpotifyWake`).
    func play(uri: String, in context: String? = nil) async throws {
        switch target {
        case .thisIPad where thisIPad == nil: throw SpotifyError.notOpenHere
        case .thisIPadIsOthers(let name): throw SpotifyError.thisIPadIsOthers(name)
        default: break
        }
        var body: [String: JSONValue] = [:]
        if let context {
            body["context_uri"] = .string(context)
            body["offset"] = ["uri": .string(uri)]
        } else if uri.hasPrefix("spotify:track:") || uri.hasPrefix("spotify:episode:") {
            body["uris"] = [.string(uri)]
        } else {
            body["context_uri"] = .string(uri)
        }
        try await command("PUT", "me/player/play", body: .object(body), onTarget: true)
    }

    func resume() async throws { try await command("PUT", "me/player/play", onTarget: true) }
    func pause() async throws { try await command("PUT", "me/player/pause") }
    func next() async throws { try await command("POST", "me/player/next") }
    func previous() async throws { try await command("POST", "me/player/previous") }

    func seek(to seconds: TimeInterval) async throws {
        try await command("PUT", "me/player/seek", query: ["position_ms": "\(Int(max(0, seconds) * 1000))"])
    }

    func setVolume(_ level: Double) async throws {
        try await command("PUT", "me/player/volume", query: ["volume_percent": "\(Int((max(0, min(1, level)) * 100).rounded()))"])
    }

    func setShuffle(_ isOn: Bool) async throws {
        try await command("PUT", "me/player/shuffle", query: ["state": isOn ? "true" : "false"])
    }

    func setRepeat(_ mode: MusicRepeatMode) async throws {
        try await command("PUT", "me/player/repeat", query: ["state": SpotifyPlayback.repeatState(for: mode)])
    }

    /// Adds a track to Spotify's queue, after the current one.
    func addToQueue(uri: String) async throws {
        try await command("POST", "me/player/queue", query: ["uri": uri], onTarget: true)
        await refreshQueue()
    }

    /// Moves playback to another Connect device and makes it the target, for the account in use.
    func transfer(to device: SpotifyDevice) async {
        chooseDevice(device.id == thisIPadID ? "" : device.id)
        await perform {
            try await client.send("PUT", "me/player", body: ["device_ids": [.string(device.id)], "play": .bool(playback?.isPlaying == true)])
        }
        await refreshAfterCommand()
    }

    /// Makes this iPad the target, and moves what plays elsewhere here when Spotify is open here.
    func useThisIPad() async {
        chooseDevice("")
        if let here = thisIPad, playback?.item != nil, playback?.device?.id != here.id {
            await transfer(to: here)
        }
    }

    /// Sends a player command, then reads the new state once Spotify has applied it.
    /// `onTarget` sends it to the chosen device when that is not the active one.
    private func command(_ method: String, _ path: String, query: [String: String] = [:], body: JSONValue? = nil,
                         onTarget: Bool = false) async throws {
        var query = query
        if onTarget, let device = targetDevice, !device.isActive { query["device_id"] = device.id }
        do {
            try await client.send(method, path, query: query, body: body)
            clearTransientProblem()
        } catch {
            note(error)
            throw error
        }
        await refreshAfterCommand()
    }

    /// Spotify reports a change a moment after it accepts it.
    private func refreshAfterCommand() async {
        try? await Task.sleep(for: .milliseconds(600))
        await refreshPlayback()
        startPolling()
    }

    /// Remembers where the account in use plays new music. Empty is this iPad.
    private func chooseDevice(_ id: String) {
        guard let owner else { return }
        accounts.update(owner) { $0.deviceID = id }
    }

    // MARK: Problems

    func note(_ error: Error) {
        if let error = error as? SpotifyError {
            problem = error
        } else if error is CancellationError {
            return
        } else if (error as? URLError)?.code != .cancelled {
            log.error("Request failed: \(String(reflecting: error), privacy: .public)")
        }
    }

    /// Clears problems a working request disproves. Sign-in problems stay until a new sign-in.
    func clearTransientProblem() {
        guard let problem, !problem.needsSignIn else { return }
        self.problem = nil
    }
}
