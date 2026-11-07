import HomePadCore
import HomePadUI
import SwiftUI

/// The "What's this song?" card: listening, the match, or why it failed.
struct SongResultOverlay: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        ZStack {
            if media.recognizer.phase != .idle {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { media.recognizer.dismiss() }
                GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.xl) {
                    card.frame(maxWidth: 520)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: media.recognizer.phase)
        .nightModeAware()
    }

    @ViewBuilder
    private var card: some View {
        switch media.recognizer.phase {
        case .idle:
            EmptyView()
        case .listening:
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "waveform")
                    .font(.system(size: 72, weight: .semibold))
                    .symbolEffect(.variableColor.iterative.reversing)
                Text("Listening…").font(.title.bold())
                Text("Hold HomePad near the music.").foregroundStyle(.secondary)
            }
        case .matched(let match):
            VStack(spacing: Theme.Spacing.l) {
                ArtworkView(url: match.artworkURL, systemImage: "music.note").frame(width: 260, height: 260)
                VStack(spacing: Theme.Spacing.xs) {
                    Text(match.title).font(.title.bold()).multilineTextAlignment(.center)
                    if let artist = match.artist { Text(artist).font(.title3).foregroundStyle(.secondary) }
                }
                HStack(spacing: Theme.Spacing.m) {
                    if match.appleMusicID != nil {
                        GlassCapsuleButton("Play", systemImage: "play.fill", isProminent: true) {
                            Task {
                                await media.perform { try await media.play(match) }
                                media.recognizer.dismiss()
                            }
                        }
                    }
                    GlassCapsuleButton("Done") { media.recognizer.dismiss() }
                }
            }
        case .failed(let message):
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "music.note.slash").font(.system(size: 60))
                Text(message).font(.title3).multilineTextAlignment(.center)
                HStack(spacing: Theme.Spacing.m) {
                    GlassCapsuleButton("Try Again", isProminent: true) { Task { await media.recognizer.identify() } }
                    GlassCapsuleButton("Done") { media.recognizer.dismiss() }
                }
            }
        }
    }
}
