import Foundation
import HomePadCore
import Observation

/// Music Assistant inside Home Assistant, as one of HomePad's two music sources.
/// It finds the integration, lists its players (HomePods, Sonos and groups), keeps
/// the speaker the person plays on, remembers which player was active last, and
/// loads the library and search results that the Music app shows.
///
/// Everything goes through `services.smartHome` (see `MusicAssistantClient`), so the
/// simulator demo swaps in `DemoMusicAssistantHome` and runs the same code.
@MainActor
@Observable
final class MusicAssistantService {
    /// Whether Music Assistant can be used.
    enum Status: Equatable {
        case unknown
        case checking
        /// Home Assistant has no Music Assistant integration, or is not connected.
        case notSetUp
        case ready(SmartHomeIntegrationEntry)
        /// The integration exists but does not answer, with a short reason.
        case failed(String)
    }

    private(set) var status: Status = .unknown
    var home = MusicAssistantHome()
    var isLoadingHome = false
    /// The Listen Now shelves loaded at least once.
    var hasLoadedHome = false
    var searchResults: MASearchResults?
    var searchQuery = ""
    var isSearching = false
    /// Last error worth showing, cleared on the next success.
    var lastError: String?
    /// The Library section's lists, by kind, once loaded (`loadLibrary`).
    var library: [MAMediaItem.MediaType: [MAMediaItem]] = [:]
    var loadingLibrary: Set<MAMediaItem.MediaType> = []

    @ObservationIgnored var client: MusicAssistantClient
    @ObservationIgnored let remote: RemotePlayerController
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private let smartHome: @MainActor () -> any SmartHomeService
    @ObservationIgnored private var lastPlayerIDs: [String] = []
    @ObservationIgnored let log = Log.make("MusicAssistant")

    init(settings: SettingsStore, remote: RemotePlayerController, smartHome: @escaping @MainActor () -> any SmartHomeService) {
        self.settings = settings
        self.remote = remote
        self.smartHome = smartHome
        client = MusicAssistantClient(smartHome: smartHome)
    }

    /// Starts watching the players, so discovery runs when they appear and the most
    /// recently active player is remembered.
    func start() {
        trackPlayers()
    }

    /// The Music Assistant user requests go to, for the member HomePad
    /// recognizes. Another user has another library and other music sources,
    /// so what showed is read again.
    func use(user: String?) {
        guard user != client.username else { return }
        client.username = user
        home = MusicAssistantHome()
        hasLoadedHome = false
        library = [:]
        searchResults = nil
        if isReady { Task { await loadHome() } }
    }

    // MARK: Status

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    var entryID: String? {
        if case .ready(let entry) = status { return entry.entryID }
        return nil
    }

    /// Asks Home Assistant for the Music Assistant config entry.
    func refreshStatus() async {
        status = .checking
        do {
            if let entry = try await client.entry() {
                status = entry.isLoaded ? .ready(entry) : .failed("Music Assistant is set up in Home Assistant but not running.")
            } else {
                status = .notSetUp
            }
        } catch SmartHomeError.notConnected {
            status = .notSetUp
        } catch SmartHomeError.unsupported {
            status = .notSetUp
        } catch {
            log.error("Discovery failed: \(error.localizedDescription, privacy: .public)")
            status = .failed("Home Assistant did not answer.")
        }
    }

    func refreshStatusIfNeeded() async {
        if status == .unknown || (!isReady && !players.isEmpty) { await refreshStatus() }
    }

    // MARK: Players

    /// Music Assistant speakers, groups first, then by room and name.
    var players: [MusicAssistantPlayer] {
        smartHome().accessories.compactMap(MusicAssistantPlayer.init(accessory:)).sorted { lhs, rhs in
            if lhs.isGroupPlayer != rhs.isGroupPlayer { return lhs.isGroupPlayer }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func player(_ id: String?) -> MusicAssistantPlayer? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }

    /// The speaker the person chose to play on, kept in settings.
    var targetPlayerID: String? {
        get {
            let id = settings[AudioSettings.musicAssistantPlayer]
            return id.isEmpty ? nil : id
        }
        set { settings[AudioSettings.musicAssistantPlayer] = newValue ?? "" }
    }

    /// Where new music plays: the chosen speaker, else one that plays (a group's leader
    /// rather than a speaker following it), else the first.
    var targetPlayer: MusicAssistantPlayer? {
        let all = players
        if let id = targetPlayerID, let chosen = all.first(where: { $0.id == id }) { return chosen }
        return all.first { $0.isPlaying && !$0.followsGroup } ?? all.first(where: \.isPlaying) ?? all.first
    }

    /// The player Now Playing follows: the chosen speaker while it plays, then any
    /// speaker that plays (the most recent first), then the last active one if it
    /// still has something loaded, then the chosen speaker if it does. A speaker
    /// that follows a group counts as the group's leader.
    var activePlayer: MusicAssistantPlayer? {
        latestPlayer.map(leader(of:))
    }

    /// A speaker that follows a group stands for its group's leader.
    func leader(of player: MusicAssistantPlayer) -> MusicAssistantPlayer {
        guard player.followsGroup, let leader = self.player(player.groupMemberIDs.first) else { return player }
        return leader
    }

    private var latestPlayer: MusicAssistantPlayer? {
        let all = players
        let target = targetPlayerID.flatMap { id in all.first { $0.id == id } }
        let lastID = settings[AudioSettings.musicAssistantLastActivePlayer]
        if let target, target.isPlaying { return target }
        let playing = all.filter(\.isPlaying)
        if let recent = playing.first(where: { $0.id == lastID }) ?? playing.first(where: { !$0.followsGroup }) ?? playing.first {
            return recent
        }
        if let last = all.first(where: { $0.id == lastID }), last.hasMedia { return last }
        return target?.hasMedia == true ? target : nil
    }

    /// The other speakers in the target's multi-room group.
    func groupMembers(of player: MusicAssistantPlayer) -> [MusicAssistantPlayer] {
        player.groupMemberIDs.filter { $0 != player.id }.compactMap(self.player)
    }

    /// Watches which players play, remembers the latest one, and checks for Music
    /// Assistant again when players appear or disappear.
    private func trackPlayers() {
        let snapshot = withObservationTracking {
            players.map { (id: $0.id, playing: $0.isPlaying) }
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPlayers() }
        }
        let playing = snapshot.filter(\.playing).map(\.id)
        let lastID = settings[AudioSettings.musicAssistantLastActivePlayer]
        let leaders = players.filter { $0.isPlaying && !$0.followsGroup }.map(\.id)
        if let newest = playing.first(where: { $0 == targetPlayerID }) ?? leaders.first ?? playing.first, !playing.contains(lastID) {
            settings[AudioSettings.musicAssistantLastActivePlayer] = newest
        }
        let ids = snapshot.map(\.id)
        if ids.isEmpty != lastPlayerIDs.isEmpty {
            Task { await refreshStatus() }
        }
        lastPlayerIDs = ids
    }
}

/// What the Music app's Listen Now shows for Music Assistant.
struct MusicAssistantHome: Equatable {
    var recentlyPlayed: [MAMediaItem] = []
    var playlists: [MAMediaItem] = []
    var recentlyAdded: [MAMediaItem] = []
    var artists: [MAMediaItem] = []
    var radio: [MAMediaItem] = []
    var favoriteTracks: [MAMediaItem] = []

    var isEmpty: Bool {
        recentlyPlayed.isEmpty && playlists.isEmpty && recentlyAdded.isEmpty && artists.isEmpty && radio.isEmpty && favoriteTracks.isEmpty
    }
}
