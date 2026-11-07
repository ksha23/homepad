import HomePadCore
import HomePadUI
import SwiftUI

/// A small analog clock widget for the Home Screen and the Modular and Photos
/// faces. Like every widget it draws its own tile, so the dial reads on a
/// wallpaper or a photo as well as on a plain face.
enum ClockWidget {
    @MainActor
    static let descriptor = WidgetDescriptor(
        id: "faces.widget.clock", title: "Clock", systemImage: "clock", supportedSizes: [.small, .medium]
    ) { _ in
        ClockWidgetView()
    }
}

private struct ClockWidgetView: View {
    @Environment(\.displayCondition) private var condition

    var body: some View {
        let palette = FacePalette.resolve(.graphite, condition: condition)
        GlassTile {
            FaceTimeline(.minute) { date in
                ZStack {
                    DialTicks(color: palette.secondary)
                    ClockHands(angles: ClockMath.angles(for: date),
                               style: .standard(ink: palette.ink, accent: palette.accent, showsSecond: false))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
