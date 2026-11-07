import HomePadUI
import SwiftUI

/// Explains one scanned code in big, readable type.
struct QRResultCard: View {
    let result: QRScanResult
    @State private var revealPassword = false

    var body: some View {
        GlassPanel(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label(result.title, systemImage: icon)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nightModeAware()
    }

    private var icon: String {
        switch result.payload {
        case .wifi: "wifi"
        case .url: "link"
        case .matter: "house.badge.wifi"
        case .homeKit: "homekit"
        case .text: "text.quote"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch result.payload {
        case .wifi(let network):
            CopyableValueRow(label: "Network", value: network.ssid)
            LabeledContent("Security", value: network.security ?? "Open")
            if let password = network.password {
                CopyableValueRow(label: "Password", value: password,
                                 displayValue: revealPassword ? nil : String(repeating: "•", count: min(12, password.count)))
                Toggle("Show Password", isOn: $revealPassword)
            }
            if network.isHidden { Text("This network is hidden. Type its name exactly when joining.").foregroundStyle(.secondary) }
            Text("Join from Settings, Wi-Fi on the device that needs it.").font(.callout).foregroundStyle(.secondary)
        case .url(let url):
            CopyableValueRow(label: "Link", value: url.absoluteString)
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                .buttonStyle(.glass)
        case .matter(let matter):
            setupCode(matter.manualPairingCode)
            LabeledContent("Vendor and Product", value: String(format: "0x%04X, 0x%04X", matter.vendorID, matter.productID))
            LabeledContent("Discovery", value: matter.discoveryDescription)
            Text("Add it with the Home app on iPhone, or with Home Assistant's Matter integration.").font(.callout).foregroundStyle(.secondary)
        case .homeKit(let homeKit):
            setupCode(homeKit.formattedCode)
            LabeledContent("Category", value: homeKit.categoryName)
            if let setupID = homeKit.setupID { LabeledContent("Setup ID", value: setupID) }
            Text("Add it with the Home app on iPhone.").font(.callout).foregroundStyle(.secondary)
        case .text(let text):
            CopyableValueRow(label: "Text", value: text)
        }
    }

    private func setupCode(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Setup Code").font(.subheadline).foregroundStyle(.secondary)
            Text(code)
                .font(.display(48))
                .monospacedDigit()
                .textSelection(.enabled)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}
