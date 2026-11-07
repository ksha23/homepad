import HomePadCore
import HomePadUI
import SwiftUI

/// Find My in Personal Info: whether everyone sees everyone's devices, and
/// whose each device is when automatic matching gets it wrong.
struct FindMySettingsSection: View {
    @Environment(FindMyService.self) private var findMy
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            Toggle("Share Devices with Everyone", isOn: settings.binding(PersonalSettings.findMyShareWithEveryone))
            if findMy.allDevices.isEmpty {
                Text("No devices yet. Add the iCloud integration or the Home Assistant app in Home Assistant.")
                    .foregroundStyle(.secondary)
            }
            ForEach(findMy.allDevices) { device in
                Picker(selection: owner(of: device)) {
                    Text(automaticTitle(for: device)).tag(FindMyOwnerChoice?.none)
                    ForEach(findMy.members) { member in
                        Text(member.name).tag(FindMyOwnerChoice?.some(.member(member.id)))
                    }
                    Text("Nobody, Admins Only").tag(FindMyOwnerChoice?.some(.nobody))
                    Text("Hidden").tag(FindMyOwnerChoice?.some(.hidden))
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.tracked.name)
                            Text(FindMyWording.sourceName(device.tracked))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsIcon(systemImage: device.kind.systemImage, tint: .green)
                    }
                }
            }
        } header: {
            Text("Find My")
        } footer: {
            Text("Each person sees their own devices, and admins see every device. Turn on sharing to let everyone see everyone's devices, as Family Sharing does. Devices that belong to nobody show only to admins. Automatic follows the person in Home Assistant, the iCloud owner, or the name, as in \"Kyle's iPhone\".")
        }
    }

    private func owner(of device: FindMyDevice) -> Binding<FindMyOwnerChoice?> {
        Binding(
            get: { findMy.ownerChoice(for: device.id) },
            set: { findMy.setOwnerChoice($0, for: device.id) }
        )
    }

    /// "Automatic (Kyle)" or "Automatic (Nobody)".
    private func automaticTitle(for device: FindMyDevice) -> String {
        let name = findMy.suggestedOwner(of: device)?.name ?? "Nobody"
        return "Automatic (\(name))"
    }
}
