import HomePadCore
import HomePadUI
import SwiftUI

/// A notification Home Assistant sent this HomePad without a command, as a
/// glass banner at the top of every screen. A tap closes it, and it closes
/// itself after a while.
struct HomeAssistantNotificationOverlay: View {
    let device: HomeAssistantDevice

    var body: some View {
        ZStack(alignment: .top) {
            if let notification = device.notification {
                GlassBanner(systemImage: "house.fill", tint: .orange,
                            title: notification.title, subtitle: notification.message)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.l)
                    .onTapGesture { device.dismissNotification() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Closes the notification")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(notification.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.4), value: device.notification)
        .nightModeAware()
    }
}
