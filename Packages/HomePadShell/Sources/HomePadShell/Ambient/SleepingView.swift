import HomePadUI
import SwiftUI

/// The near-black screen shown while nobody is around. OLED pixels stay off
/// except for a faint, drifting time. The first touch only wakes the display
/// (the kiosk sees it through the touch observer), it never presses whatever
/// was underneath.
struct SleepingView: View {
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        ZStack {
            Color.black
            TimelineView(.everyMinute) { context in
                Text(context.date.clockTime())
                    .font(.display(44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.12))
                    .offset(x: kiosk.burnInOffset.width * 6, y: kiosk.burnInOffset.height * 6)
                    .animation(Theme.Motion.ambient, value: kiosk.burnInOffset)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityLabel("Display sleeping. Tap to wake.")
    }
}
