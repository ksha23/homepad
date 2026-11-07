import HomePadUI
import SwiftUI

/// The Mirror's edge ring light: a soft band of light around the screen edge
/// that lights a face in a dark room, with the preview inset inside it.
struct RingLightView<Content: View>: View {
    let level: RingLightLevel
    let tone: RingLightTone
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let band = min(proxy.size.width, proxy.size.height) * level.bandFraction
            ZStack {
                // The light itself fills the screen, and the preview covers all
                // but the band. A blurred inner edge makes it read as a glow.
                Rectangle()
                    .fill(level == .off ? Color.black : tone.color)
                    .ignoresSafeArea()
                content
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .padding(max(band, Theme.Spacing.m))
                    .shadow(color: tone.color.opacity(level == .off ? 0 : 0.9), radius: band * 0.6)
            }
            .animation(.smooth(duration: 0.5), value: level)
            .animation(.smooth(duration: 0.5), value: tone)
        }
    }
}
