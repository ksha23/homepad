import HomePadCore
import HomePadUI
import SwiftUI

/// One device, like Apple's device card: where it is (with its street
/// address), when it was last seen, battery and accuracy, and Play Sound with
/// what happened to it.
struct FindMyDeviceCard: View {
    let device: FindMyDevice
    let onBack: () -> Void
    @Environment(FindMyService.self) private var findMy

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            GlassIconButton("chevron.backward", label: "All Devices", size: Theme.Size.toolbarItem, action: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header
                    location
                    facts
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            FindMySoundControl(device: device)
        }
        .padding(Theme.Spacing.m)
        .task(id: spotKey) {
            _ = await findMy.address(for: device.tracked)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            FindMyDeviceIcon(device: device, size: Theme.Size.tapTarget)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(FindMyWording.placeLabel(device.tracked, address: address))
                .font(.title3.weight(.semibold))
            if let address, device.tracked.place != .away {
                Text(address)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text(device.tracked.place == .unknown ? "Last heard from" : "Last seen")
                LastSeenText(date: device.tracked.lastUpdated)
            }
            .font(.tileDetail)
            .foregroundStyle(.secondary)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.m) {
                FindMyBatteryLabel(device: device.tracked)
                if let accuracy = device.tracked.accuracy {
                    Label(FindMyWording.accuracy(accuracy), systemImage: "scope")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.tileDetail)
            Text(FindMyWording.source(device.tracked))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Sam · iPhone 16", or just the model.
    private var detail: String? {
        let parts = [device.owner?.name, device.tracked.model].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var address: String? { findMy.cachedAddress(for: device.tracked) }

    /// Changes when the device moves to another spot, so the address is looked up again.
    private var spotKey: String {
        guard let latitude = device.tracked.latitude, let longitude = device.tracked.longitude else { return device.id }
        return device.id + FindMyAddressBook.key(latitude, longitude)
    }
}

/// Play Sound and what happened: sending, sent or why it failed. Devices that
/// cannot ring say so instead of offering a button that would fail.
struct FindMySoundControl: View {
    let device: FindMyDevice
    @Environment(FindMyService.self) private var findMy

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if device.tracked.canPlaySound {
                GlassCapsuleButton("Play Sound", systemImage: "speaker.wave.2.fill", size: .large, isProminent: true) {
                    Task { try? await findMy.playSound(device) }
                }
                .disabled(state == .sending)
                if let state {
                    Label(state.message, systemImage: symbol(for: state))
                        .font(.tileDetail)
                        .foregroundStyle(isFailure ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .contentTransition(.opacity)
                        .animation(Theme.Motion.standard, value: state)
                }
            } else {
                Label(FindMyService.cannotRing(device).localizedDescription, systemImage: "speaker.slash")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var state: FindMySoundState? { findMy.soundStates[device.id] }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func symbol(for state: FindMySoundState) -> String {
        switch state {
        case .sending: "arrow.up.circle"
        case .sent: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
