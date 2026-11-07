import HomePadCore
import HomePadUI
import SwiftUI

/// The one-tap "Play on Living Room?" card, shown when playback starts somewhere
/// other than the preferred speaker. The button is the system route picker,
/// since iOS lets only the person choose AirPlay speakers.
struct RoutePromptOverlay: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        VStack {
            Spacer()
            if let prompt = media.routePrompt {
                GlassBanner(
                    systemImage: "hifispeaker.fill",
                    title: "Play on \(prompt.speakerName)?",
                    subtitle: "Playing on \(media.routes.currentRouteName) now."
                ) {
                    EmptyView()
                } actions: {
                    AirPlayButton(size: Theme.Size.tapTarget, isGlass: true)
                    GlassCapsuleButton("Not Now") { media.routePrompt = nil }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: media.routePrompt)
    }
}
