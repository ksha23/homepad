import HomePadCore
import HomePadUI
import SwiftUI

/// Where a change made here to someone's phone calendar or list stands:
/// saving, waiting for the phone, or not saved. Shown on the event or reminder itself.
struct PhoneChangeLabel: View {
    let status: PhoneWriteStatus
    let deviceName: String
    var isCompact = false

    var body: some View {
        if isCompact {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
        }
    }

    var title: String {
        switch status.state {
        case .sending: "Saving on \(deviceName)"
        case .waiting: "Waiting for \(deviceName)"
        case .failed: "Not saved on \(deviceName)"
        }
    }

    private var symbol: String {
        switch status.state {
        case .sending: "arrow.triangle.2.circlepath"
        case .waiting: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status.state {
        case .sending: .secondary
        case .waiting: .orange
        case .failed: .red
        }
    }
}
