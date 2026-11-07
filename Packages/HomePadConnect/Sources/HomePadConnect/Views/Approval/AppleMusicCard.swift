import HomePadCore
import HomePadUI
import SwiftUI

/// On an iPhone, in a HomePad's remote, once the iPhone is linked to someone
/// there: Use My Apple Music. While that HomePad recognizes them, its Music
/// app shows their own library, playlists, recently played and recommendations.
struct AppleMusicCard: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    @State private var isChanging = false

    private var sharing: AppleMusicSharing { connect.appleMusicSharing }
    private var member: ApprovalMember? { connect.approvals.states[peer.id]?.linkedMember }
    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }

    var body: some View {
        if connect.link.identity.kind == .iPhone, let member, let homePad {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Use My Apple Music", systemImage: "music.note")
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if homePad.supportsMemberAppleMusic {
                        content(member)
                    } else {
                        Text("Update HomePad on \(peer.name) to show your Apple Music there.")
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
        let isOn = sharing.isSharing(with: peer.id)
        Toggle(isOn: Binding(get: { isOn }, set: change)) {
            Text("Show my Apple Music on \(peer.name)").font(.headline)
        }
        .disabled(isChanging || sharing.busy.contains(peer.id))
        Text("While \(peer.name) recognizes \(member.name), its Music app shows \(member.name)'s library, playlists, recently played and recommendations. Nobody else at \(peer.name) sees them.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text("Songs play through the Apple Music account on \(peer.name), so what plays there counts toward that account, not yours. Songs you uploaded to your library can't play there.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if isOn {
            status
        } else {
            Text("This iPhone gives \(peer.name) a token that reads your Apple Music library. It goes over your home network only, stays on that iPad and is deleted when you turn this off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var status: some View {
        if sharing.busy.contains(peer.id) {
            Label("Sending to \(peer.name)", systemImage: "arrow.up.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let state = sharing.states[peer.id], state.needsToken {
            Label("\(peer.name) needs a new Apple Music token. It gets one the next time HomePad is open on this iPhone.",
                  systemImage: "arrow.clockwise")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Linked. \(peer.name) has your Apple Music.", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let note = sharing.notes[peer.id] {
            Label(note, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
