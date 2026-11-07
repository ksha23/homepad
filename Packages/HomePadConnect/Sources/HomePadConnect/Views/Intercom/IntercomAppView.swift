import HomePadCore
import HomePadUI
import SwiftUI

/// The Intercom app on a HomePad: push to talk on the left, history on the right.
struct IntercomAppView: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        AppScreen("Intercom") {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if connect.link.homePads.isEmpty { setupHint }
                GeometryReader { proxy in
                    if proxy.size.width > proxy.size.height {
                        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                            IntercomPanel(buttonDiameter: min(proxy.size.height * 0.45, 380))
                                .frame(maxHeight: .infinity)
                            IntercomHistoryList()
                                .frame(width: proxy.size.width * 0.4)
                        }
                    } else {
                        VStack(spacing: Theme.Spacing.xl) {
                            IntercomPanel(buttonDiameter: min(proxy.size.width * 0.4, 340))
                            IntercomHistoryList()
                        }
                    }
                }
            }
        }
    }

    private var setupHint: some View {
        StatusBanner(connect.link.household == nil
                     ? "Pair your other HomePads, iPhone and Mac in Settings, Devices & Sharing to talk to them."
                     : "No other HomePads are reachable right now. Messages reach them once they are on this Wi-Fi.",
                     systemImage: "info.circle.fill", tint: .secondary)
    }
}
