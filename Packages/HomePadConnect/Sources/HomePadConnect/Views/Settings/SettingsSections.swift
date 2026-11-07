import HomePadCore
import HomePadUI
import SwiftUI

/// Household membership: show a pairing code, join another household, or leave.
struct HouseholdSection: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect
    @State private var confirmLeave = false

    var body: some View {
        Section {
            if let window = connect.link.pairingWindow, window.isOpen() {
                PairingCodeCard(window: window) { connect.link.closePairingWindow() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if connect.isHomePad {
                Button("Show Pairing Code", systemImage: "number") { connect.link.openPairingWindow() }
            }
            NavigationLink {
                // A page pushed onto Settings' stack takes the stack's environment, not this section's,
                // so the module's runtime goes with it. Without it, Join a Household crashed on a HomePad.
                JoinHouseholdView().environment(connect)
            } label: {
                Label(connect.link.household == nil ? "Join a HomePad Household" : "Join a Different Household",
                      systemImage: "person.badge.plus")
            }
            if connect.link.household != nil {
                Button("Leave Household", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLeave = true
                }
                // On the row, not the section: a section hands its modifiers to
                // every row, and the dialog's popover would point at another row.
                .confirmationDialog("Leave this household?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Leave Household", role: .destructive) { connect.link.leaveHousehold() }
                } message: {
                    Text("This device stops receiving intercom messages, shared items and alerts until you pair it again.")
                }
            }
        } header: {
            Text(connect.link.household.map { "Household: \($0.name)" } ?? "Household")
        } footer: {
            Text("Paired devices share intercom, Send to HomePad, the Family Board and alerts. Devices signed in to the same Apple Account pair through iCloud Keychain automatically.")
        }
    }
}

/// Intercom choices: a fixed set of toggles and clip lengths.
struct IntercomSettingsSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Section("Intercom") {
            Toggle("Play Messages When They Arrive", isOn: services.settings.binding(ConnectSettings.intercomAutoPlay))
            Toggle("Quiet in Night Mode", isOn: services.settings.binding(ConnectSettings.intercomQuietAtNight))
            Toggle("Read Typed Announcements Aloud", isOn: services.settings.binding(ConnectSettings.intercomSpeakText))
            Picker("Longest Message", selection: services.settings.binding(ConnectSettings.intercomMaxSeconds)) {
                ForEach(IntercomHub.clipLengths, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
            }
        }
    }
}

/// Which alerts reach phones and Macs, plus the optional Home Assistant notify service.
struct AlertRelaySettingsSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Section {
            ForEach(RelayedAlert.allCases) { alert in
                Toggle(isOn: binding(for: alert)) {
                    Label(alert.title, systemImage: alert.systemImage)
                }
            }
            DisclosureGroup("Home Assistant") {
                TextField("notify.mobile_app_your_iphone", text: services.settings.binding(ConnectSettings.alertNotifyService))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
        } header: {
            Text("Alerts on iPhone and Mac")
        } footer: {
            Text("When this HomePad hears an alarm or the doorbell rings, paired iPhones and Macs get a notification. Add a Home Assistant notify service to also reach phones that are away or asleep. Do not rely on HomePad in an emergency.")
        }
    }

    private func binding(for alert: RelayedAlert) -> Binding<Bool> {
        Binding(
            get: { services.settings[ConnectSettings.relayedAlerts].contains(alert) },
            set: { isOn in
                var alerts = services.settings[ConnectSettings.relayedAlerts].filter { $0 != alert }
                if isOn { alerts.append(alert) }
                services.settings[ConnectSettings.relayedAlerts] = alerts
            }
        )
    }
}
