import HomePadCore
import HomePadUI
import SwiftUI

/// On a HomePad, in Devices & Sharing: the phones and Macs that approve
/// unlocks here, with a way to stop each one.
struct PersonalDevicesSection: View {
    @Environment(ConnectRuntime.self) private var connect

    private var approver: PersonalDeviceApprover { connect.approver }

    var body: some View {
        Section {
            if approver.store.devices.isEmpty {
                Text("No personal devices yet.").foregroundStyle(.secondary)
            }
            ForEach(approver.store.devices) { device in
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text("Unlocks \(approver.memberName(device.memberID))'s apps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: device.kind.systemImage)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { approver.remove(device.id) }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Personal Devices")
        } footer: {
            Text("A person's own iPhone or Mac can approve opening their personal apps here with Use Personal Device. To set one up, open HomePad on it, pick this HomePad and choose who uses it, then allow it here.")
        }
        .onAppear { approver.pruneLinks() }
    }
}
