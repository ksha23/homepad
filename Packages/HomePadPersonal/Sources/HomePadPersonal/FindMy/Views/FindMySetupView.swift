import HomePadCore
import HomePadUI
import SwiftUI

/// What Find My says when it has no devices to show, and what to set up in
/// Home Assistant to get them.
struct FindMySetupView: View {
    let setup: FindMyService.Setup
    let viewerName: String?

    var body: some View {
        EmptyStateView(title, message: message, systemImage: systemImage)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch setup {
        case .ready: ""
        case .noHomeAssistant: "Connect Home Assistant"
        case .noTrackers: "No Devices Yet"
        case .nothingForViewer: viewerName.map { "No Devices for \($0)" } ?? "No Devices"
        }
    }

    private var message: String {
        switch setup {
        case .ready:
            ""
        case .noHomeAssistant:
            "Find My shows the iPhones, iPads and other devices that Home Assistant tracks, and can make them play a sound. Connect Home Assistant in Settings, under Smart Home. Then add the iCloud integration in Home Assistant, or the Home Assistant app on each device."
        case .noTrackers:
            "In Home Assistant, add the iCloud integration with your Apple Account to see every device on that account, including Family Sharing. Or install the Home Assistant app on each iPhone and iPad and allow location. Devices appear here as soon as Home Assistant has them."
        case .nothingForViewer:
            "Each person sees their own devices, and admins see all of them. An admin can choose whose each device is, or share every device with everyone, in Settings, under Personal Info."
        }
    }

    private var systemImage: String {
        switch setup {
        case .ready, .noTrackers: "location.slash"
        case .noHomeAssistant: "house.and.flag"
        case .nothingForViewer: "person.crop.circle.badge.questionmark"
        }
    }
}

/// The header's small link to Apple's Find My, for what Home Assistant cannot
/// see: AirTags, AirPods and items.
struct OpenFindMyButton: View {
    @Environment(\.openURL) private var openURL
    private let url = URL(string: "findmy://")!

    var body: some View {
        if UIApplication.shared.canOpenURL(url) {
            GlassCapsuleButton("Open Find My", systemImage: "arrow.up.forward.app") { openURL(url) }
        }
    }
}
