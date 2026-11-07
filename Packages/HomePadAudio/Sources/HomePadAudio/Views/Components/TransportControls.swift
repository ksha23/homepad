import HomePadCore
import HomePadUI
import SwiftUI

/// Back, play or pause, and forward for the Now Playing widget, as tall as
/// `height`. Play is a square and back and forward are at least
/// `Theme.Size.minTapTarget` wide, so every button is a whole target. The
/// symbols are a large share of the height, so they read from a step back.
struct TransportControls: View {
    @Environment(AudioMediaService.self) private var media
    /// The buttons' height, at least `Theme.Size.minTapTarget`.
    let height: CGFloat
    /// False for play or pause alone, where there is no room for the others.
    var showsSkip = true

    var body: some View {
        let nowPlaying = media.nowPlaying
        let canSkip = media.canSkip
        HStack(spacing: Theme.Spacing.controlGap) {
            if showsSkip {
                button("backward.fill", label: "Previous", enabled: canSkip, isPlay: false) { await media.previousTrack() }
            }
            button(nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                   label: nowPlaying?.isPlaying == true ? "Pause" : "Play", enabled: nowPlaying != nil, isPlay: true) {
                await media.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            if showsSkip {
                button("forward.fill", label: "Next", enabled: canSkip, isPlay: false) { await media.nextTrack() }
            }
        }
    }

    private func button(_ symbol: String, label: String, enabled: Bool, isPlay: Bool,
                        action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            // Play is the main control, so it is a square of the full height with the
            // larger symbol. Back and forward are narrower beside it. A row shorter than
            // `Theme.Size.tapTarget` reaches up and down to it without moving anything.
            Image(systemName: symbol)
                .font(.system(size: height * (isPlay ? Self.playScale : Self.skipScale), weight: .semibold))
                .frame(width: isPlay ? height : max(Theme.Size.minTapTarget, height * 0.75), height: height)
                .padding(.vertical, verticalReach)
                .contentShape(Rectangle())
                .padding(.vertical, -verticalReach)
        }
        .buttonStyle(.pressable)
        .foregroundStyle(.primary.opacity(enabled ? 1 : 0.35))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The play or pause symbol's point size as a share of the height: about
    /// 38 points at `Theme.Size.tapTarget` and 26 at `Theme.Size.minTapTarget`.
    static let playScale: CGFloat = 0.6
    /// Back and forward, a little smaller than play, as on iPadOS.
    static let skipScale: CGFloat = 0.42

    /// How far the touch area reaches above and below a button to make it
    /// `Theme.Size.tapTarget` tall.
    private var verticalReach: CGFloat {
        max(0, (Theme.Size.tapTarget - height) / 2)
    }
}
