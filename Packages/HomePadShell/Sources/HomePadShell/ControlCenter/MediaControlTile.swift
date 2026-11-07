import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center's media tile, like iPadOS: artwork and the AirPlay button on
/// top, the title (two lines) and artist, then big transport buttons. Tapping
/// the artwork or title opens Now Playing, or Music when nothing plays.
struct MediaControlTile: View {
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellNavigator.self) private var navigator

    var body: some View {
        let nowPlaying = services.media.nowPlaying
        GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    Button(action: openPlayer) { artwork(nowPlaying) }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(nowPlaying == nil ? "Open Music" : "Open Now Playing")
                    Spacer(minLength: 0)
                    AirPlayButton()
                }
                Button(action: openPlayer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying?.title ?? "Not Playing")
                            .font(.headline)
                            .lineLimit(2)
                        Text(nowPlaying.map { $0.artist ?? $0.outputName ?? "" } ?? "Tap to choose music")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // A new song's title and artist crossfade in.
                    .animation(Theme.Motion.standard, value: nowPlaying?.title)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                HStack {
                    transportButton("backward.fill", label: "Previous") { await services.media.previousTrack() }
                    Spacer()
                    transportButton(nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                                    label: nowPlaying?.isPlaying == true ? "Pause" : "Play") {
                        if services.media.nowPlaying?.isPlaying == true {
                            await services.media.pause()
                        } else {
                            await services.media.play()
                        }
                    }
                    .font(.largeTitle)
                    Spacer()
                    transportButton("forward.fill", label: "Next") { await services.media.nextTrack() }
                }
                .font(.title)
                .disabled(nowPlaying == nil)
                .opacity(nowPlaying == nil ? 0.4 : 1)
                // Play turns into pause when the player answers, wherever it was started.
                .animation(Theme.Motion.standard, value: nowPlaying?.isPlaying)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The same cover the Now Playing widget shows, from the module that plays,
    /// which crossfades between tracks. Loading `artworkURL` here showed a
    /// music note whenever the cover came from Apple Music or the library.
    private func artwork(_ nowPlaying: NowPlaying?) -> some View {
        Group {
            if let nowPlaying, let cover = registry.nowPlayingArtwork {
                cover(nowPlaying, Theme.Radius.tileControl)
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.12))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tileControl, style: .continuous))
    }

    private func transportButton(_ systemImage: String, label: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressable(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func openPlayer() {
        if services.media.nowPlaying != nil {
            navigator.openNowPlaying()
        } else {
            navigator.open(appID: KnownAppID.music)
        }
    }
}
