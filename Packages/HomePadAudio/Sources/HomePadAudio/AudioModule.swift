import HomePadCore
import HomePadUI
import SwiftUI

/// Music from curated sources (This iPad with Apple Music and the synced library,
/// Music Assistant through Home Assistant, and Spotify when turned on), AirPlay routing, internet radio, sleep
/// sounds, house-wide Now Playing and song recognition. Installs `AudioMediaService`
/// as `services.media`.
public enum AudioModule: HomePadModule {
    public static let id = "audio"
    static let nowPlayingAppID = "nowplaying"
    static let musicAppID = "music"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let media = AudioMediaService(services: services)
        services.media = media
        // A person who takes the household's ID for them keeps their queue, place and Spotify on this iPad.
        let settings = services.settings
        services.household.onMemberIDChange { [weak media] old, new in
            media?.spotify.accounts.moveMember(from: old, to: new)
            settings.moveValue(fromKeyNamed: AudioSettings.memberMusicState(ownerKey: old.uuidString).name,
                               toKeyNamed: AudioSettings.memberMusicState(ownerKey: new.uuidString).name)
            if settings[AudioSettings.musicQueueOwner] == old.uuidString {
                settings[AudioSettings.musicQueueOwner] = new.uuidString
            }
        }

        registry.register(app: AppDescriptor(
            id: musicAppID, title: "Music", systemImage: "music.note", tint: .pink, category: .media, sortOrder: 21
        ) { MusicAppView().environment(media) })
        // Now Playing is Music's full-screen player, not an app of its own, so
        // the pill opens the app that plays. "nowplaying" (the pill, widgets,
        // Control Center, links) opens Music with the player up.
        registry.register(redirect: AppRedirect(id: nowPlayingAppID, opens: musicAppID) {
            media.openPlayer()
        })

        registry.register(control: ControlDescriptor(id: "audio.identify", title: "What's This Song?", sortOrder: 31) {
            SongRecognitionControlTile().environment(media)
        })

        // Music playing asks a widget stack to show Now Playing.
        registry.register(widget: WidgetDescriptor(id: "audio.nowplaying", title: "Now Playing", systemImage: "play.circle.fill", opensApp: Self.nowPlayingAppID,
                                                   relevance: { _ in media.nowPlaying?.isPlaying == true ? .ongoing() : nil }) { size in
            NowPlayingWidgetView(size: size).environment(media)
        })

        registry.register(settings: SettingsPaneDescriptor(id: "audio", title: "Audio & AirPlay", systemImage: "airplayaudio", tint: .pink, sortOrder: 40) {
            AudioSettingsPane().environment(media)
        })

        registry.register(overlay: OverlayDescriptor(id: "audio.routePrompt", zIndex: 40) {
            RoutePromptOverlay().environment(media)
        })
        registry.register(overlay: OverlayDescriptor(id: "audio.songResult", zIndex: 60) {
            SongResultOverlay().environment(media)
        })

        registry.register(nowPlayingArtwork: { nowPlaying, cornerRadius in
            NowPlayingArtwork(nowPlaying: nowPlaying, cornerRadius: cornerRadius).environment(media)
        })
        registry.register(tools: AudioAssistantTools.make(media: media))
        AppleMusicLibraryRefresh.register(in: services.backgroundWork, media: media)
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        (services.media as? AudioMediaService)?.start()
    }
}
