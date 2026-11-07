import HomePadUI
import SwiftUI
import UIKit

/// Live Guided Access status, a setup guide, and a button that asks iPadOS for
/// Autonomous Single App Mode (works only on a supervised iPad whose MDM
/// profile allows HomePad).
struct GuidedAccessSection: View {
    @State private var isEnabled = UIAccessibility.isGuidedAccessEnabled
    @State private var isRequesting = false
    @State private var result: String?

    var body: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: isEnabled ? "lock.fill" : "lock.open")
                    Text(isEnabled ? "Locked to HomePad" : "Off")
                }
                .foregroundStyle(isEnabled ? .green : .secondary)
            }
            DisclosureGroup("Set Up Guided Access") {
                NumberedSteps(steps: [
                    "Open the iPad's Settings app and go to Accessibility > Guided Access.",
                    "Turn on Guided Access.",
                    "Tap Passcode Settings and set a Guided Access passcode. Turn on Face ID too if you like.",
                    "Set Display Auto-Lock to Never.",
                    "Turn on Accessibility Shortcut so a triple-click starts Guided Access.",
                    "Come back to HomePad and triple-click the top button, then tap Start.",
                    "To leave, triple-click again and enter the passcode.",
                ])
            }
            Button {
                request(enable: !isEnabled)
            } label: {
                Label(isEnabled ? "End Single App Mode" : "Start Autonomous Single App Mode",
                      systemImage: "lock.rectangle.stack")
            }
            .disabled(isRequesting)
            if let result {
                Text(result).font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("How Autonomous Single App Mode Works") {
                Text("""
                Autonomous Single App Mode lets HomePad lock itself in with no triple-click, \
                and come back after a restart. iPadOS only allows it on a supervised iPad \
                with a configuration profile whose autonomousSingleAppModePermittedAppIDs \
                restriction lists com.ksha23.homepad.
                """)
                NumberedSteps(steps: [
                    "On a Mac, install Apple Configurator from the App Store.",
                    "Back up the iPad, then connect it with a cable.",
                    "In Apple Configurator choose Prepare, pick Manual Configuration and turn on Supervise Devices. This erases the iPad.",
                    "Install a profile with the restriction above, from Apple Configurator or from any MDM service.",
                    "Install HomePad again, then tap Start Autonomous Single App Mode here.",
                ])
            }
        } header: {
            Text("Guided Access")
        } footer: {
            Text("Guided Access keeps HomePad on screen and blocks the Home gesture, so the iPad works like a dedicated home display.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            isEnabled = UIAccessibility.isGuidedAccessEnabled
        }
    }

    private func request(enable: Bool) {
        isRequesting = true
        UIAccessibility.requestGuidedAccessSession(enabled: enable) { success in
            isRequesting = false
            isEnabled = UIAccessibility.isGuidedAccessEnabled
            if success {
                result = enable ? "HomePad is now locked in single app mode." : "Single app mode ended."
            } else {
                result = """
                iPadOS declined. This iPad is not supervised with a profile that allows HomePad. \
                Use Guided Access above instead.
                """
            }
        }
    }
}

/// A numbered list of short steps for setup guides.
struct NumberedSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(step)
                }
            }
        }
        .font(.callout)
        .padding(.vertical, Theme.Spacing.xs)
    }
}
