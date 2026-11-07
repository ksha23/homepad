import HomePadCore
import HomePadUI
import SwiftUI

/// On a HomePad: "Let Kyle's iPhone unlock Kyle's apps?" when a phone or Mac
/// asks to approve for a member. Allow needs that member recognized here, or
/// the iPad owner's Face ID or passcode. It goes away on its own after two
/// minutes, and the phone is told.
struct LinkRequestOverlay: View {
    @Environment(ConnectRuntime.self) private var connect
    @State private var isAllowing = false

    private var approver: PersonalDeviceApprover { connect.approver }

    var body: some View {
        VStack {
            if let pending = approver.pendingLinks.first {
                banner(pending)
            }
            Spacer()
        }
        .animation(Theme.Motion.settle, value: approver.pendingLinks.first?.id)
    }

    private func banner(_ pending: PersonalDeviceApprover.PendingLink) -> some View {
        let member = connect.services.household.members.first { $0.id == pending.memberID }
        let name = member?.name ?? "Someone"
        return GlassBanner(
            systemImage: pending.deviceKind.systemImage,
            tint: member.map { Color(hex: $0.colorHex) } ?? .accentColor,
            title: "Let \(pending.deviceName) unlock \(name)'s apps?",
            subtitle: "Allow it only if it's \(name)'s own \(pending.deviceKind.displayName). It can then approve opening \(name)'s personal apps here."
        ) {
            EmptyView()
        } actions: {
            GlassCapsuleButton("Don't Allow") { approver.decline(pending) }
            GlassCapsuleButton("Allow", isProminent: true) {
                isAllowing = true
                Task {
                    await approver.allow(pending)
                    isAllowing = false
                }
            }
            .disabled(isAllowing)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
