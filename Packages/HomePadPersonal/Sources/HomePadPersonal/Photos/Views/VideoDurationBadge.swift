import HomePadUI
import SwiftUI

/// A video's length on its thumbnail, bottom trailing, like the Photos app.
struct VideoDurationBadge: View {
    let duration: TimeInterval

    var body: some View {
        Label(Self.text(for: duration), systemImage: "play.fill")
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(Theme.Spacing.xs)
            .accessibilityLabel("Video, \(Duration.seconds(duration.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))")
    }

    /// "0:42", "12:05", "1:02:10".
    static func text(for duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }
}
