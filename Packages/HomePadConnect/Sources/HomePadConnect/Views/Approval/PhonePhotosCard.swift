import HomePadCore
import HomePadUI
import SwiftUI

/// On an iPhone, in a HomePad's remote, once the iPhone is linked to someone
/// there: Show My Photos. While that HomePad recognizes them, it shows this
/// iPhone's photo library in its Photos app.
struct PhonePhotosCard: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    @State private var isChanging = false

    private var sharing: PhoneLibraryServer { connect.photoSharing }
    private var member: ApprovalMember? { connect.approvals.states[peer.id]?.linkedMember }
    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }

    var body: some View {
        if connect.link.identity.kind == .iPhone, let member, let homePad {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Show My Photos", systemImage: "photo.on.rectangle")
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if homePad.supportsPhonePhotos {
                        content(member)
                    } else {
                        Text("Update HomePad on \(peer.name) to show the photos on this iPhone there.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                if let error = sharing.errors[peer.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ member: ApprovalMember) -> some View {
        Toggle(isOn: Binding(get: { sharing.isSharing(with: peer.id) }, set: change)) {
            Text("Show my photos on \(peer.name)").font(.headline)
        }
        .disabled(isChanging)
        Text("While \(peer.name) recognizes \(member.name), its Photos app shows the photos on this iPhone. They go over your home network only, never to a server, and nobody else at \(peer.name) sees them.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if sharing.isSharing(with: peer.id) {
            if let problem = sharing.wakeProblem {
                Label(problem, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(peer.name) wakes HomePad on this iPhone over Bluetooth when it recognizes \(member.name), even while HomePad is closed. If you force quit HomePad or restart this iPhone, open HomePad once so \(peer.name) can reach it again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let served = sharing.lastServed[peer.id] {
                Text("Last sent \(served.formatted(.relative(presentation: .named))).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func change(_ isOn: Bool) {
        isChanging = true
        Task {
            await sharing.setSharing(isOn, with: peer.id)
            isChanging = false
        }
    }
}
