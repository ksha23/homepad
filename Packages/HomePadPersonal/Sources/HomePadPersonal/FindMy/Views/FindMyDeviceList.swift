import HomePadCore
import HomePadUI
import SwiftUI

/// The devices, grouped by owner like Apple's Devices tab: the viewer's own
/// first, then each other person's, then devices nobody owns.
struct FindMyDeviceList: View {
    let devices: [FindMyDevice]
    let viewerID: UUID?
    @Binding var selection: TrackedDevice.ID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.top, Theme.Spacing.s)
                    ForEach(group.devices) { device in
                        Button {
                            selection = device.id
                        } label: {
                            FindMyDeviceRow(device: device, isSelected: selection == device.id)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                Text("AirTags, AirPods and items are in Apple's Find My.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(Theme.Spacing.s)
            }
            .padding(Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
    }

    private var groups: [(title: String, devices: [FindMyDevice])] {
        var result: [(title: String, devices: [FindMyDevice])] = []
        for device in devices {
            let title = groupTitle(for: device)
            if let index = result.firstIndex(where: { $0.title == title }) {
                result[index].devices.append(device)
            } else {
                result.append((title, [device]))
            }
        }
        return result
    }

    private func groupTitle(for device: FindMyDevice) -> String {
        guard let owner = device.owner else { return "Other Devices" }
        if owner.id == viewerID { return "My Devices" }
        return "\(owner.name.split(separator: " ").first ?? Substring(owner.name))'s Devices"
    }
}

/// One device in the list: icon, name, where and when, and battery.
struct FindMyDeviceRow: View {
    let device: FindMyDevice
    let isSelected: Bool
    @Environment(FindMyService.self) private var findMy

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            FindMyDeviceIcon(device: device)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                    .font(.tileTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(FindMyWording.placeLabel(device.tracked, address: findMy.cachedAddress(for: device.tracked).map(FindMyWording.street)))
                        .lineLimit(1)
                    Text("·")
                    LastSeenText(date: device.tracked.lastUpdated)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.tileDetail)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FindMyBatteryLabel(device: device.tracked)
                .font(.tileDetail)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.Size.tapTarget)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.primary.opacity(isSelected ? 0.16 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
