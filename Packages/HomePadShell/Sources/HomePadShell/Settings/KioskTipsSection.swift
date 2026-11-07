import HomePadUI
import SwiftUI

/// Tips for running an iPad as an always-on display: reopen HomePad when power
/// returns, keep Auto-Lock as a backup, and protect the battery.
struct KioskTipsSection: View {
    var body: some View {
        Section("Always On Tips") {
            tip("Open HomePad When Charging Starts", systemImage: "bolt.badge.automatic") {
                NumberedSteps(steps: [
                    "Open the Shortcuts app and tap Automation.",
                    "Tap New Automation and choose Charger.",
                    "Pick Is Connected and Run Immediately.",
                    "Add the Open App action and choose HomePad.",
                ])
                Text("After a restart or a power cut, HomePad comes back on its own as soon as the iPad charges.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            tip("Auto-Lock", systemImage: "lock.display") {
                Text("""
                HomePad keeps the screen on while it is open. As a backup, set Settings > Display & \
                Brightness > Auto-Lock to Never, so the iPad stays awake if another app is in front.
                """)
            }
            tip("Battery Health", systemImage: "battery.100percent.bolt") {
                Text("""
                An iPad that is always plugged in should not sit at full charge. In Settings > Battery, \
                turn on the 80% Limit if your iPad offers it, or Optimized Battery Charging. Keep the iPad \
                out of direct sun and away from heat.
                """)
            }
        }
    }

    private func tip(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        let body = content()
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                body
            }
            .font(.callout)
            .padding(.vertical, Theme.Spacing.xs)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
