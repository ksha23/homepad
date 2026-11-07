import Foundation
import HomePadCore

/// Settings owned by the Audio module. Curated choices only, Apple style.
enum AudioSettings {
    /// Keep the microphone (wake word, sound alerts) available while radio and
    /// sleep sounds play. Costs them AirPlay 2 multi-room: the system then allows
    /// only one AirPlay speaker. Apple Music and the library are not affected,
    /// since Apple's player has its own session and route. On by default: a voice
    /// assistant that stops hearing its wake word whenever radio plays to a HomePod
    /// is worse than one speaker at a time.
    static let preferMicrophone = SettingKey<Bool>("audio.preferMicrophone", default: true)

    /// Name of the speaker HomePad should play on, for example "Living Room".
    /// Empty means no preference.
    static let preferredSpeaker = SettingKey<String>("audio.preferredSpeaker", default: "", syncsWithICloud: true)

    /// Show a one-tap prompt when playback starts somewhere other than the preferred speaker.
    static let promptForPreferredSpeaker = SettingKey<Bool>("audio.promptForPreferredSpeaker", default: true)

    /// Stop playback when headphones disconnect, so sleep sounds never jump to the speaker.
    static let pauseWhenHeadphonesDisconnect = SettingKey<Bool>("audio.pauseOnHeadphonesDisconnect", default: true)
    /// Now Playing hides its controls a few seconds after the last touch and
    /// shows the artwork full screen (`NowPlayingPoster`). Off by default.
    static let nowPlayingFullScreenArtwork = SettingKey<Bool>("audio.nowPlaying.fullScreenArtwork", default: false)

    /// Default sleep timer in minutes, chosen from `SleepTimer.choices`. Zero means off.
    static let defaultSleepTimerMinutes = SettingKey<Int>("audio.sleep.defaultMinutes", default: 45, syncsWithICloud: true)

    /// IDs of the sleep sound presets shown in the Sleep section, in order.
    static let sleepPresetIDs = SettingKey<[String]>(
        "audio.sleep.presets", default: SleepPreset.defaultIDs, syncsWithICloud: true
    )

    /// Favorite radio station IDs, in the order the person arranged them.
    static let favoriteStationIDs = SettingKey<[String]>(
        "audio.radio.favorites", default: CuratedStations.defaultFavoriteIDs, syncsWithICloud: true
    )

    /// Stations the person added by URL or saved from search.
    static let savedStations = SettingKey<[RadioStation]>("audio.radio.saved", default: [], syncsWithICloud: true)

    /// Most recently played stations, newest first.
    static let recentStations = SettingKey<[RadioStation]>("audio.radio.recents", default: [])

    /// Where Apple Music was: the queue's source, the song and the moment, so a
    /// restart continues there. Saved on this iPad only.
    static let appleMusicResume = SettingKey<MusicResumePoint?>("audio.appleMusic.resume", default: nil)

    /// The last volume the person chose for each set of AirPlay speakers Apple's
    /// player played to (`MusicVolumeMemory`). Saved on this iPad only.
    static let musicVolumes = SettingKey<MusicVolumeMemory>("audio.music.volumes", default: MusicVolumeMemory())

    /// The local source that played last ("appleMusic", "radio" and so on), so a
    /// restart only offers to continue Apple Music when that was the last thing.
    static let lastLocalSource = SettingKey<String>("audio.lastLocalSource", default: "")

    /// Base URL of the Music Assistant web UI, for example "http://homeassistant.local:8095".
    /// Empty hides the optional Music Assistant panel.
    static let musicAssistantURL = SettingKey<String>("audio.musicAssistant.url", default: "")

    /// The household's music source, a `MusicSource` raw value. A member's own choice,
    /// kept in their preferences under `musicSourcePreference`, wins while they use HomePad.
    static let musicSource = SettingKey<String>("audio.musicSource", default: MusicSource.thisIPad.rawValue, syncsWithICloud: true)

    /// The `HouseholdMember.preferences` key for a member's own music source.
    static let musicSourcePreference = "audio.musicSource"

    /// Accessory ID of the Music Assistant speaker new music plays on. Empty means the first one.
    static let musicAssistantPlayer = SettingKey<String>("audio.musicAssistant.player", default: "")

    /// Accessory ID of the Music Assistant player that played most recently, for Now Playing.
    static let musicAssistantLastActivePlayer = SettingKey<String>("audio.musicAssistant.lastActive", default: "")

    /// Recent searches in the Music app, newest first.
    static let recentSearches = SettingKey<[String]>("audio.music.recentSearches", default: [])

    /// Offers Spotify as a third music source. Off until the person sets it up.
    static let spotifyEnabled = SettingKey<Bool>("audio.spotify.enabled", default: false)

    /// Where the one Spotify sign-in kept the Connect device new music played on,
    /// before each account had a record (`SpotifyAccountRecord.deviceID`). Read
    /// once into the household's record, then cleared.
    static let spotifyDeviceID = SettingKey<String>("audio.spotify.device", default: "")

    /// Where the one Spotify sign-in kept this iPad's Connect device ID, before
    /// each account had a record (`SpotifyAccountRecord.thisIPadID`). Read once
    /// into the household's record, then cleared.
    static let spotifyThisIPadID = SettingKey<String>("audio.spotify.thisIPad", default: "")

    /// The `HouseholdMember.preferences` key for the Music Assistant user a
    /// member's requests go to (`username` in Home Assistant's Music Assistant
    /// actions), so Music Assistant uses the music sources that user may use,
    /// such as their own Spotify account. Empty or missing sends none.
    static let musicAssistantUserPreference = "audio.musicAssistant.user"

    /// Whose queue the iPad's player holds (`MusicQueueOwner.key`), so after a
    /// restart the saved place (`appleMusicResume`) is filed under the right person.
    static let musicQueueOwner = SettingKey<String>("audio.music.queueOwner", default: "")

    /// One owner's queue, place, shuffle, repeat and recently played, on this iPad only.
    /// One key per owner, so a save writes only that person's state.
    static func memberMusicState(ownerKey: String) -> SettingKey<MemberMusicState?> {
        SettingKey("audio.music.member.\(ownerKey)", default: nil)
    }
}
