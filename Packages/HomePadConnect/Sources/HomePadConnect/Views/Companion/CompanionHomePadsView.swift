import HomePadCore
import HomePadUI
import SwiftUI

/// The companion's first tab: the household's HomePads, pairing and settings.
struct CompanionHomePadsView: View {
    @Environment(ConnectRuntime.self) private var connect
    /// `-HomePadOpenApp devices` opens Devices & Sharing, for simulator screenshots.
    @State private var showsSettings = UserDefaults.standard.string(forKey: "HomePadOpenApp") == "devices"
    /// `-HomePadOpenApp homepad` or `music` opens the first HomePad's remote or its
    /// music as soon as it is found, for simulator screenshots.
    @State private var launchScreen = UserDefaults.standard.string(forKey: "HomePadOpenApp")
    @State private var openedRemote: PeerDevice?
    @State private var openedMusic: PeerDevice?

    private var link: PeerLink { connect.link }

    var body: some View {
        NavigationStack {
            List {
                if link.household == nil {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Label("Pair with Your HomePad", systemImage: "ipad.landscape.badge.play")
                                .font(.title3.bold())
                            Text("On the HomePad, open Settings, Devices & Sharing and tap Show Pairing Code.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                        NavigationLink("Enter Pairing Code") { JoinHouseholdView() }
                    }
                } else {
                    Section("My HomePads") {
                        if link.homePads.isEmpty {
                            Text("Looking for your HomePads on this network.").foregroundStyle(.secondary)
                        }
                        ForEach(link.homePads) { peer in
                            NavigationLink {
                                HomePadRemoteView(peer: peer)
                            } label: {
                                PeerRow(peer: peer, status: connect.remote.status(of: peer.id))
                            }
                        }
                    }
                    if !link.companions.isEmpty {
                        Section("Other Devices") {
                            ForEach(link.companions) { PeerRow(peer: $0, status: nil) }
                        }
                    }
                }
                if let problem = link.problem {
                    Section { Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.orange) }
                }
            }
            .navigationTitle(link.household?.name ?? "HomePad")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
            .sheet(isPresented: $showsSettings) {
                // The stack is for the pages the settings push, such as
                // Join a Household, which keep the system bar and its back button.
                NavigationStack {
                    SheetScreen("Devices & Sharing") {
                        DevicesSettingsView()
                    }
                }
            }
            .refreshable { await connect.remote.refresh() }
            .onChange(of: link.homePads) {
                connect.sharing.publishTargets()
                openLaunchScreen()
            }
            .navigationDestination(item: $openedRemote) { HomePadRemoteView(peer: $0) }
            .navigationDestination(item: $openedMusic) { HomePadMusicView(peer: $0) }
        }
    }
}

extension CompanionHomePadsView {
    /// Opens the screen `-HomePadOpenApp` asked for, once, when the first HomePad shows up.
    private func openLaunchScreen() {
        guard let screen = launchScreen, let first = link.homePads.first else { return }
        switch screen {
        case "homepad": openedRemote = first
        case "music": openedMusic = first
        default: return
        }
        launchScreen = nil
    }
}

/// One device with its kind, connection and what it is doing.
struct PeerRow: View {
    let peer: PeerDevice
    let status: HomePadStatus?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: peer.kind.systemImage)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(peer.isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
                .accessibilityLabel(peer.isConnected ? "Connected" : "Not connected")
        }
    }

    private var detail: String {
        if let playing = status?.nowPlaying { return "Playing \(playing)" }
        let running = status?.timers.filter { $0.status == .running }.count ?? 0
        if running > 0 { return running == 1 ? "1 timer running" : "\(running) timers running" }
        return peer.kind.displayName
    }
}
