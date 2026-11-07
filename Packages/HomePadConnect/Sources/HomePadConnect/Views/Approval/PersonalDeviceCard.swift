import HomePadCore
import HomePadUI
import SwiftUI

/// On a companion, in a HomePad's remote: use this iPhone or Mac to approve
/// unlocks on that HomePad. Pick who uses the device, then allow it on the
/// HomePad. Once linked, the HomePad's Use Personal Device asks this device.
struct PersonalDeviceCard: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice

    private var approvals: ApprovalResponder { connect.approvals }
    private var state: ApprovalLinkState? { approvals.states[peer.id] }
    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }
    private var kind: DeviceKind { connect.link.identity.kind }
    private var biometry: String { kind == .mac ? "Touch ID" : "Face ID" }

    var body: some View {
        if let homePad {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Unlock With This \(kind.displayName)", systemImage: "lock.open")
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if homePad.supportsPersonalDevices {
                        content
                    } else {
                        Text("Update HomePad on \(peer.name) to approve its personal apps from this \(kind.displayName).")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                if let error = approvals.linkErrors[peer.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            }
            .task(id: homePad.supportsPersonalDevices) {
                if homePad.supportsPersonalDevices { await approvals.requestState(of: peer.id) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let member = state?.linkedMember {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(member: household(member), size: Theme.Size.minTapTarget)
                Text("Unlocks \(member.name)'s apps on \(peer.name)").font(.headline)
            }
            Text("When \(member.name) opens a personal app there, such as Messages, approve it here with \(biometry) or the passcode.")
                .foregroundStyle(.secondary)
            GlassCapsuleButton("Stop Unlocking", systemImage: "lock", size: .regular) {
                Task { await approvals.linkMember(nil, on: peer.id) }
            }
        } else if let member = state?.pendingMember {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(member: household(member), size: Theme.Size.minTapTarget)
                Text("Allow it on \(peer.name)").font(.headline)
            }
            Text("Tap Allow on \(peer.name) to let this \(kind.displayName) unlock \(member.name)'s apps there.")
                .foregroundStyle(.secondary)
        } else if let members = state?.members, !members.isEmpty {
            Text("Approve personal apps on \(peer.name), such as Messages, with \(biometry) on this \(kind.displayName). Who uses it?")
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(members) { member in
                        Button {
                            link(member)
                        } label: {
                            VStack(spacing: Theme.Spacing.xs) {
                                AvatarView(member: household(member), size: Theme.Size.tapTarget)
                                Text(member.name).font(.subheadline)
                            }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("This \(kind.displayName) is \(member.name)'s")
                    }
                }
            }
        } else {
            Text(state == nil ? "Connecting to \(peer.name)." : "Add people on \(peer.name) first, in Settings, People.")
                .foregroundStyle(.secondary)
        }
    }

    private func link(_ member: ApprovalMember) {
        Task {
            // The prompt can reach this device as a notification while HomePad is in the background.
            await connect.alerts.requestAuthorization()
            await approvals.linkMember(member, on: peer.id)
        }
    }

    /// The avatar view takes a household member.
    private func household(_ member: ApprovalMember) -> HouseholdMember {
        HouseholdMember(id: member.id, name: member.name, avatar: member.avatar, colorHex: member.colorHex)
    }
}
