import HomePadCore
import HomePadUI
import SwiftUI

/// Settings, Devices & Sharing: room name, household pairing, devices,
/// intercom, alert relay, Handoff and Family Board sync. A grouped Form so it
/// reads like iOS Settings, on the HomePad and in the companion.
struct DevicesSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect

    private var link: PeerLink { connect.link }

    var body: some View {
        Form {
            if connect.isHomePad { roomSection }
            HouseholdSection()
            if connect.isHomePad { SharedSetupSection() }
            devicesSection
            if connect.isHomePad { PersonalDevicesSection() }
            IntercomSettingsSection()
            if connect.isHomePad { AlertRelaySettingsSection() }
            handoffSection
            boardSection
        }
        .navigationTitle("Devices & Sharing")
    }

    private var roomSection: some View {
        Section {
            Picker("Room", selection: roomBinding) {
                Text("Not Set").tag("")
                ForEach(roomChoices, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("This HomePad")
        } footer: {
            Text("Other devices see this HomePad by its room, and intercom messages from it say \"Intercom from \(link.identity.name)\".")
        }
    }

    private var roomBinding: Binding<String> {
        Binding(
            get: { services.settings[ConnectSettings.roomName] },
            set: {
                services.settings[ConnectSettings.roomName] = $0
                link.refreshIdentity()
            }
        )
    }

    /// Rooms from the smart home plus common ones. A curated list, not free text.
    private var roomChoices: [String] {
        let common = ["Kitchen", "Living Room", "Family Room", "Dining Room", "Bedroom", "Kids Room", "Guest Room",
                      "Office", "Entryway", "Hallway", "Basement", "Garage"]
        var seen = Set<String>()
        return (services.smartHome.rooms + common).filter { seen.insert($0.lowercased()).inserted }
    }

    private var devicesSection: some View {
        Section {
            if link.members.isEmpty {
                Text(link.household == nil ? "Pair a device to see it here." : "No other devices found on this network yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(link.members) { peer in
                HStack {
                    Label(peer.name, systemImage: peer.kind.systemImage)
                    Spacer()
                    Text(peer.isConnected ? "Connected" : "Nearby").foregroundStyle(.secondary)
                }
            }
            Toggle("Local Network Link", isOn: Binding(
                get: { services.settings[ConnectSettings.linkEnabled] },
                set: { enabled in
                    services.settings[ConnectSettings.linkEnabled] = enabled
                    enabled ? link.start() : link.stop()
                }
            ))
        } header: {
            Text("Devices")
        } footer: {
            if let problem = link.problem { Text(problem).foregroundStyle(.orange) }
        }
    }

    private var handoffSection: some View {
        Section {
            Toggle("Recipes", isOn: services.settings.binding(ConnectSettings.handoffRecipes))
            Toggle("Now Playing", isOn: services.settings.binding(ConnectSettings.handoffNowPlaying))
            Toggle("Assistant Conversations", isOn: services.settings.binding(ConnectSettings.handoffAssistant))
        } header: {
            Text("Handoff")
        } footer: {
            Text("Pick up what is on this screen on your iPhone, iPad or Mac signed in to the same Apple Account.")
        }
    }

    private var boardSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { services.settings[ConnectSettings.boardICloudSync] },
                set: { connect.board.setICloudSync($0) }
            ))
            if services.settings[ConnectSettings.boardICloudSync] {
                LabeledContent("Status", value: connect.board.cloud.status.text)
            }
        } header: {
            Text("Family Board")
        } footer: {
            Text("Paired devices always share notes over your network. iCloud also reaches your devices away from home.")
        }
    }
}
