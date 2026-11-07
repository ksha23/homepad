import HomePadCore
import HomePadUI
import SwiftUI

/// Devices & Sharing, Shared Setup: how many of the household's HomePads this
/// one shares its people, Home Screens and faces with, and when it last
/// synced. Face recognition is set up on each HomePad, so it also names who
/// still needs to set it up on this one.
struct SharedSetupSection: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect

    private var setup: HouseholdSetupSync { connect.setup }

    var body: some View {
        Section {
            LabeledContent {
                if let lastSync = setup.lastSync { Text(Self.timeText(lastSync)) }
            } label: {
                Label(statusText, systemImage: "arrow.triangle.2.circlepath")
            }
            if !needsFaceSetup.isEmpty {
                Label("Set up face recognition here for \(needsFaceSetup.formatted(.list(type: .and)))",
                      systemImage: "faceid")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Shared Setup")
        } footer: {
            Text(footerText)
        }
    }

    private var statusText: String {
        let count = setup.syncedPeers.count
        if connect.link.household == nil { return "Not Paired" }
        if count == 0 { return setup.sharesSetup ? "Waiting for Other HomePads" : "Not Synced Yet" }
        return count == 1 ? "Synced with 1 HomePad" : "Synced with \(count) HomePads"
    }

    private var footerText: String {
        var text = "People, their Home Screens and wallpapers, and saved faces are the same on every HomePad in the household."
        let names = setup.syncedPeers.map(\.name)
        if !names.isEmpty { text += " This HomePad shares them with \(names.formatted(.list(type: .and)))." }
        text += " The room, face recognition, photos picked from this iPad's library and the settings of widgets with"
            + " Same on All HomePads turned off stay on each HomePad."
        return text
    }

    /// The people with no face recognition on this HomePad yet, while it is on.
    private var needsFaceSetup: [String] {
        guard services.settings[CoreSettings.faceRecognitionEnabled] else { return [] }
        return services.household.members.filter { !$0.hasFaceEnrollment }.map(\.name)
    }

    /// "2:41 PM" today, otherwise the date too.
    static func timeText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}
