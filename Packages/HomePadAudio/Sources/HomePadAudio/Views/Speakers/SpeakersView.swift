import HomePadCore
import HomePadUI
import SwiftUI

/// Every place music can play: this iPad's AirPlay route, Music Assistant's
/// speakers and groups with what each plays and its volume, and other Home
/// Assistant speakers. Grouping happens in the Play On panel.
struct SpeakersView: View {
    let openPicker: () -> Void
    let openMusicAssistant: () -> Void
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(spacing: Theme.Spacing.m) {
                    GlassCapsuleButton("Choose Speakers", systemImage: "hifispeaker.2.fill", isProminent: true, tint: .pink, action: openPicker)
                    if !services.settings[AudioSettings.musicAssistantURL].isEmpty {
                        GlassCapsuleButton("Open Music Assistant", systemImage: "arrow.up.forward.app", action: openMusicAssistant)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Theme.Spacing.l)], alignment: .leading,
                          spacing: Theme.Spacing.l) {
                    ThisIPadSpeakerCard()
                    ForEach(media.musicAssistant.players) { player in
                        SpeakerCard(player: player)
                    }
                }
                if media.spotify.isReady {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader("Spotify", systemImage: "dot.radiowaves.up.forward")
                        GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.l) {
                            SpotifyDevicePicker().frame(maxWidth: 560, alignment: .leading)
                        }
                    }
                }
                if !otherSpeakers.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader("Other Home Assistant Speakers", systemImage: "hifispeaker")
                        Text("These play radio and resume on their own. Add them to Music Assistant to search and group them.")
                            .font(.tileDetail)
                            .foregroundStyle(.secondary)
                        ForEach(otherSpeakers) { OtherSpeakerRow(speaker: $0) }
                    }
                }
                if media.musicAssistant.players.isEmpty {
                    musicAssistantHint
                }
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .onAppear { media.routes.beginDetection() }
        .onDisappear { media.routes.endDetection() }
    }

    /// Home Assistant speakers that Music Assistant does not manage.
    private var otherSpeakers: [AudioOutput] {
        media.outputs.filter { $0.kind == .homeAssistantPlayer && media.musicAssistant.player($0.id) == nil }
    }

    private var musicAssistantHint: some View {
        GlassBanner(systemImage: "hifispeaker.2.fill", tint: .pink, title: "Play on HomePods and Sonos from HomePad",
                    subtitle: "Add Music Assistant to Home Assistant and add your speakers as players there. They show up here, play on their own and group for multi-room.")
    }
}

/// This iPad: its AirPlay route, with the system picker for HomePods.
private struct ThisIPadSpeakerCard: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    Image(systemName: "ipad.landscape").font(.largeTitle).foregroundStyle(.secondary)
                    Spacer()
                    AirPlayButton(size: Theme.Size.tapTarget, isGlass: true)
                }
                Text("This iPad").font(.title2.bold())
                Text(media.musicOutputName.map { "Plays on \($0)" } ?? "Plays on the speakers picked in AirPlay").font(.headline).foregroundStyle(.secondary)
                Text(media.isHeadphonesActive ? "Playing on \(media.currentRouteName)." : "Choose several HomePods in AirPlay to play in many rooms.")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(height: 240)
    }
}

/// A Home Assistant speaker outside Music Assistant, with a control button.
private struct OtherSpeakerRow: View {
    let speaker: AudioOutput
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "hifispeaker.fill").font(.title2).foregroundStyle(Theme.tint(for: .mediaPlayer))
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name).font(.tileTitle)
                Text(media.remotePlayers.nowPlaying(on: speaker.id).map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " · ") } ?? "Idle")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            GlassCapsuleButton(media.remoteTargetID == speaker.id ? "Controlling" : "Control") {
                Task { await media.perform { try await media.select(outputID: speaker.id) } }
            }
            .disabled(media.remoteTargetID == speaker.id)
        }
        .padding(Theme.Spacing.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
