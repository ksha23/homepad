import HomePadCore
import HomePadUI
import SwiftUI

/// Now Playing once nobody has touched it for a few seconds, as HomeView's idle
/// player: the cover as tall (or, upright, as wide) as the screen, never
/// cropped, fading into the artwork wash on the side it does not reach, with
/// the title and artist large at the bottom left. Nothing moves until the
/// track changes, and then the cover and text crossfade.
struct NowPlayingPoster: View {
    let nowPlaying: NowPlaying

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isLandscape = size.width >= size.height
            let side = min(size.width, size.height)
            cover(side: side, isLandscape: isLandscape)
                .frame(width: size.width, height: size.height, alignment: isLandscape ? .leading : .top)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                details(titleSize: min(76, min(proxy.size.width, proxy.size.height) * 0.08))
                    .frame(maxWidth: proxy.size.width * 0.66, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(Theme.Spacing.l)
            .animation(.smooth(duration: 0.5), value: nowPlaying.title)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Touch to show the controls")
    }

    private func cover(side: CGFloat, isLandscape: Bool) -> some View {
        NowPlayingArtwork(nowPlaying: nowPlaying, cornerRadius: 0)
            .frame(width: side, height: side)
            // Beside the cover the title sits on the cover itself, so a shade at
            // its foot keeps white text readable over a bright one.
            .overlay(alignment: .bottom) {
                if isLandscape {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                        .frame(height: side * 0.45)
                }
            }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                               startPoint: isLandscape ? .leading : .top,
                               endPoint: isLandscape ? .trailing : .bottom)
            }
    }

    private func details(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(nowPlaying.title)
                .font(.system(size: titleSize, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let artist = nowPlaying.artist {
                Text(artist)
                    .font(.system(size: titleSize * 0.55, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 16)
        .id(nowPlaying.title)
        .transition(.opacity)
    }
}
