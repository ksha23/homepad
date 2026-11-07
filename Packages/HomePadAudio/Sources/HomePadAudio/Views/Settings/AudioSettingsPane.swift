import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > Audio & AirPlay. Curated choices in a standard grouped list.
struct AudioSettingsPane: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @State private var showsAddStation = false
    /// `-HomePadSpotifySetup YES` opens Spotify's setup, for screenshots.
    @State private var opensSpotifySetup = UserDefaults.standard.bool(forKey: "HomePadSpotifySetup")

    var body: some View {
        let settings = services.settings
        Form {
            MusicSourceSettingsSections()
            speakerSection(settings)
            Section {
                Toggle("Keep Microphone On While Playing", isOn: Binding(
                    get: { settings[AudioSettings.preferMicrophone] },
                    set: { settings[AudioSettings.preferMicrophone] = $0; media.applySessionPreference() }
                ))
                Toggle("Pause When Headphones Disconnect", isOn: settings.binding(AudioSettings.pauseWhenHeadphonesDisconnect))
            } header: {
                Text("AirPlay and Microphone")
            } footer: {
                Text("Apple Music and your library play on as many HomePods as you pick in AirPlay, with the microphone on, and HomePad sets their volume. This setting is for radio and sleep sounds. With it on, your wake word works while they play, on one AirPlay speaker at a time. Turn it off to play them on several HomePods at once. The wake word then pauses while they play.")
            }
            Section {
                Toggle("Artwork Fills the Screen", isOn: settings.binding(AudioSettings.nowPlayingFullScreenArtwork))
            } header: {
                Text("Now Playing")
            } footer: {
                Text("Six seconds after the last touch, Now Playing hides its controls and shows the artwork as large as the screen, with the song's title. A touch brings the controls back.")
            }
            sleepSection(settings)
            radioSection
        }
        .sheet(isPresented: $showsAddStation) { AddStationSheet().environment(media) }
        .navigationDestination(isPresented: $opensSpotifySetup) {
            SpotifySetupView().environment(media).environment(services)
        }
    }

    private func speakerSection(_ settings: SettingsStore) -> some View {
        Section {
            Picker("Preferred Speaker", selection: settings.binding(AudioSettings.preferredSpeaker)) {
                Text("None").tag("")
                ForEach(speakerNames(settings), id: \.self) { Text($0).tag($0) }
            }
            Toggle("Offer to Switch Speakers", isOn: settings.binding(AudioSettings.promptForPreferredSpeaker))
            Button("Choose Speakers…") { media.showRoutePicker() }
        } header: {
            Text("AirPlay From This iPad")
        } footer: {
            Text("When music starts somewhere else, HomePad offers your preferred speaker with one tap. Pick it once in AirPlay so it shows up in this list.")
        }
    }

    /// Speakers HomePad knows by name: the current route, Home Assistant speakers and the saved choice.
    private func speakerNames(_ settings: SettingsStore) -> [String] {
        var names = media.routes.ports.filter { $0.kind == .airPlay }.map(\.name)
        names += media.outputs.filter { $0.kind == .homeAssistantPlayer }.map(\.name)
        names.append(settings[AudioSettings.preferredSpeaker])
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func sleepSection(_ settings: SettingsStore) -> some View {
        Section("Sleep Sounds") {
            Picker("Default Sleep Timer", selection: settings.binding(AudioSettings.defaultSleepTimerMinutes)) {
                ForEach(SleepTimer.choices, id: \.self) { Text(SleepTimer.label(minutes: $0)).tag($0) }
            }
            ForEach(SleepPreset.all) { preset in
                Toggle(isOn: Binding(
                    get: { settings[AudioSettings.sleepPresetIDs].contains(preset.id) },
                    set: { isOn in
                        var ids = settings[AudioSettings.sleepPresetIDs].filter { $0 != preset.id }
                        if isOn { ids.append(preset.id) }
                        settings[AudioSettings.sleepPresetIDs] = ids
                    }
                )) {
                    Label(preset.title, systemImage: preset.sound.systemImage)
                }
            }
        }
    }

    private var radioSection: some View {
        Section {
            ForEach(media.radioLibrary.favorites) { station in
                Label(station.name, systemImage: "star.fill")
            }
            .onMove { media.radioLibrary.moveFavorites(from: $0, to: $1) }
            .onDelete { offsets in
                offsets.map { media.radioLibrary.favorites[$0] }.forEach(media.radioLibrary.toggleFavorite)
            }
            Button("Add Station by URL…") { showsAddStation = true }
        } header: {
            Text("Favorite Stations")
        } footer: {
            Text("Swipe to remove. Add favorites from Music > Radio by touching and holding a station.")
        }
    }
}
