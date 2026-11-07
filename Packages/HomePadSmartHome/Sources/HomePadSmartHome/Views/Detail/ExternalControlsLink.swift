import HomePadCore
import HomePadUI
import SwiftUI

/// "Open in Home Assistant" or "Open in Home App", for settings HomePad does not show natively.
struct ExternalControlsLink: View {
    @Environment(DashboardNavigator.self) private var navigator
    @Environment(\.openURL) private var openURL
    let path: String?
    let backend: SmartHomeBackend

    /// For an accessory: its Home Assistant history page, where every attribute and more-info dialog lives.
    init(accessory: HomeAccessory) {
        backend = accessory.backend
        path = "/history?entity_id=\(BackendID.localID(of: accessory.id))"
    }

    /// For a camera: the person's Home Assistant dashboard, which has its own camera cards.
    init(camera: HomeCamera) {
        backend = camera.backend
        path = nil
    }

    var body: some View {
        switch backend {
        case .homeAssistant:
            Button("Open in Home Assistant", systemImage: "arrow.up.forward.app") {
                navigator.open(path: path ?? "")
            }
            .buttonStyle(.glass)
        case .homeKit:
            Button("Open in Home App", systemImage: "house") {
                if let url = URL(string: "com.apple.home://") { openURL(url) }
            }
            .buttonStyle(.glass)
        case .demo:
            EmptyView()
        }
    }
}
