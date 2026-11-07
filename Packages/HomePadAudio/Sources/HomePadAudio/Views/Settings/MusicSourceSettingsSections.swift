import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// The music sections of Settings > Audio & AirPlay: the source choice, Apple Music's
/// live status on this iPad, Music Assistant's status and speaker, and Spotify.
struct MusicSourceSettingsSections: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL

    var body: some View {
        sourceSection
        appleMusicSection
        musicAssistantSection
        MusicAssistantUsersSection()
        SpotifySettingsSection()
    }

    private var sourceSection: some View {
        Section {
            if media.canChooseMusicSource {
                Picker("Music Source", selection: Binding(get: { media.preferredMusicSource }, set: { media.setMusicSource($0) })) {
                    ForEach(media.availableMusicSources) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } else {
                LabeledContent("Music Source", value: MusicSource.thisIPad.title)
            }
        } header: {
            Text("Music Source")
        } footer: {
            Text(sourceFooter)
        }
    }

    private var sourceFooter: String {
        guard media.canChooseMusicSource else {
            return "Music plays on this iPad. Add Music Assistant to Home Assistant, or turn on Spotify below, to play on speakers by themselves."
        }
        let who = services.household.activeMember.map { "Remembered for \($0.name)." } ?? "Remembered for the household."
        return "\(media.preferredMusicSource.detail) \(who)"
    }

    private var appleMusicSection: some View {
        Section {
            LabeledContent("Apple Music", value: media.catalog.status.title)
            LabeledContent("Music Library", value: libraryStatus)
            switch media.catalog.status {
            case .notAuthorized(true):
                Button("Connect Apple Music") { Task { await media.connectAppleMusic() } }
            case .notAuthorized(false):
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            default:
                Button("Check Again") { Task { await media.catalog.refreshStatus(force: true) } }
            }
        } header: {
            Text("Apple Music on This iPad")
        } footer: {
            Text(media.catalog.status.message)
        }
        .task { await media.catalog.refreshStatus() }
    }

    private var libraryStatus: String {
        switch media.mediaLibrary.authorization {
        case .authorized: media.mediaLibrary.hasContent ? "Synced" : "Empty"
        case .notDetermined: "Not Connected"
        default: "Not Allowed"
        }
    }

    private var musicAssistantSection: some View {
        Section {
            LabeledContent("Status", value: musicAssistantStatus)
            if media.musicAssistant.isReady {
                Picker("Plays On", selection: Binding(
                    get: { media.musicAssistant.targetPlayer?.id ?? "" },
                    set: { media.musicAssistant.targetPlayerID = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(media.musicAssistant.players) { Text($0.name).tag($0.id) }
                }
            }
            TextField("Web panel, for example homeassistant.local:8095",
                      text: services.settings.binding(AudioSettings.musicAssistantURL))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Music Assistant")
        } footer: {
            Text("HomePad uses Music Assistant through Home Assistant, so it needs no address of its own. The optional web panel address adds Open Music Assistant to the Music app.")
        }
        .task { await media.musicAssistant.refreshStatusIfNeeded() }
    }

    private var musicAssistantStatus: String {
        switch media.musicAssistant.status {
        case .unknown, .checking: "Checking"
        case .notSetUp: "Not Set Up in Home Assistant"
        case .ready: "\(media.musicAssistant.players.count) Speakers"
        case .failed(let reason): reason
        }
    }
}
