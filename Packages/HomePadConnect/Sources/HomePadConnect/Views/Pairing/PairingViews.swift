import HomePadCore
import HomePadUI
import SwiftUI

/// The host side: a big 6-digit code with a countdown, shown while a new
/// device joins.
struct PairingCodeCard: View {
    let window: PairingWindow
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Enter this code on your iPhone, Mac or other HomePad")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(PairingCode.formatted(window.code))
                .font(.display(72, weight: .bold))
                .monospacedDigit()
                .textSelection(.enabled)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(window.expiresAt.timeIntervalSince(context.date)))
                Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GlassCapsuleButton("Stop Pairing", action: onCancel)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .nightModeAware()
    }
}

/// The joining side: pick a HomePad that shows a code, type the code, join.
struct JoinHouseholdView: View {
    @Environment(ConnectRuntime.self) private var connect
    @Environment(\.dismiss) private var dismiss
    @State private var hostID: String?
    @State private var code = ""
    @State private var isJoining = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if connect.link.pairableHomePads.isEmpty {
                    Label("On your HomePad, open Settings, Devices & Sharing, then tap Show Pairing Code.",
                          systemImage: "ipad.landscape")
                        .foregroundStyle(.secondary)
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Picker("HomePad", selection: $hostID) {
                        ForEach(connect.link.pairableHomePads) { peer in
                            Label(peer.name, systemImage: peer.kind.systemImage).tag(Optional(peer.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } header: {
                Text("HomePads Showing a Code")
            }
            Section {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospacedDigit())
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.orange)
                }
            }
            Section {
                Button(action: join) {
                    HStack {
                        Text("Join Household")
                        Spacer()
                        if isJoining { ProgressView() }
                    }
                }
                .disabled(hostID == nil || PairingCode.normalize(code) == nil || isJoining)
            }
        }
        .navigationTitle("Join a Household")
        .onChange(of: connect.link.pairableHomePads) { _, peers in
            if hostID == nil || !peers.contains(where: { $0.id == hostID }) { hostID = peers.first?.id }
        }
        .onAppear { hostID = connect.link.pairableHomePads.first?.id }
    }

    private func join() {
        guard let hostID else { return }
        isJoining = true
        error = nil
        Task {
            do {
                try await connect.link.join(hostID, code: code)
                if !connect.isHomePad { await connect.alerts.requestAuthorization() }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isJoining = false
        }
    }
}
