import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center tile: "What's This Song?" with ShazamKit.
struct SongRecognitionControlTile: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        Button {
            Task { await media.recognizer.identify() }
        } label: {
            GlassTile(isHighlighted: media.recognizer.isListening, tint: .blue) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Image(systemName: "shazam.logo.fill")
                        .font(.system(size: 30))
                        .symbolEffect(.pulse, isActive: media.recognizer.isListening)
                    Spacer(minLength: 0)
                    Text(media.recognizer.isListening ? "Listening…" : "What's This Song?")
                        .font(.headline)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
