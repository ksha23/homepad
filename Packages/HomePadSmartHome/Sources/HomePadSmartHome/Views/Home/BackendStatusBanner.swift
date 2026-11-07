import HomePadCore
import HomePadUI
import SwiftUI

/// A calm one-line notice when the Home app is not showing real data. Problems
/// (Apple Home without homes or access, Home Assistant offline) sit above the
/// content, where they explain stale tiles. The demo notice is only information,
/// so it waits at the end of the page instead of pushing the accessories down.
struct BackendStatusBanner: View {
    enum Placement {
        /// Problems with a backend.
        case top
        /// The demo notice.
        case bottom
    }

    @Environment(UnifiedSmartHomeService.self) private var service
    let placement: Placement

    var body: some View {
        let notices = notices
        // Nothing at all when there is no notice, so the page adds no gap for it.
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(notices, id: \.text) { notice in
                    StatusBanner(notice.text, systemImage: notice.symbol, tint: .secondary)
                }
            }
        }
    }

    private struct Notice {
        var text: String
        var symbol: String
    }

    private var notices: [Notice] {
        switch placement {
        case .top: problems
        case .bottom: service.isShowingDemo ? [Notice(text: "Showing demo accessories. Connect Home Assistant or Apple Home in Settings, Smart Home.", symbol: "sparkles")] : []
        }
    }

    private var problems: [Notice] {
        var result: [Notice] = []
        let homeKit = service.homeKit
        if homeKit.access == .authorized, homeKit.homes.isEmpty {
            result.append(Notice(text: "Apple Home has no homes on this iPad yet.", symbol: "house"))
        } else if homeKit.access == .denied {
            result.append(Notice(text: "Apple Home access is off. Turn it on in the iPad's Settings app.", symbol: "house.slash"))
        }
        let homeAssistant = service.homeAssistant
        if homeAssistant.isConfigured, !homeAssistant.status.isConnected {
            result.append(Notice(text: "Home Assistant: \(homeAssistant.status.summary)", symbol: "wifi.exclamationmark"))
        }
        return result
    }
}
