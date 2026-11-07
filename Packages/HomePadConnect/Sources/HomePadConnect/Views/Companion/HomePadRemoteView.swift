import HomePadCore
import HomePadUI
import SwiftUI

/// Remote control for one HomePad: its music, switch its face or app, run timers, ask the assistant.
struct HomePadRemoteView: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    @State private var prompt = ""
    @State private var error: String?

    private var status: HomePadStatus? { connect.remote.status(of: peer.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                HomePadMusicCard(peer: peer)
                TimersSection(timers: status?.timers ?? [], target: peer.id)
                askField
                if let faces = status?.faces, !faces.isEmpty {
                    ChoiceGrid(title: "Faces", systemImage: "clock", choices: faces) { send(.showFace(id: $0.id)) }
                }
                if let apps = status?.apps, !apps.isEmpty {
                    ChoiceGrid(title: "Apps", systemImage: "square.grid.2x2", choices: apps) { send(.openApp(id: $0.id)) }
                }
                PersonalDeviceCard(peer: peer)
                PhonePhotosCard(peer: peer)
                AppleMusicCard(peer: peer)
                PhoneCalendarsCard(peer: peer)
                SpotifySignInCard(peer: peer)
                if status == nil {
                    ProgressView("Connecting to \(peer.name)").frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .defaultScrollAnchor(Self.startAnchor)
        .navigationTitle(peer.name)
        .toolbar {
            Button("Show Face", systemImage: "rectangle.on.rectangle") { send(.goAmbient) }
        }
        .task {
            while !Task.isCancelled {
                await connect.remote.refresh(peer.id)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .watchesMusic(of: peer.id)
    }

    /// `-ConnectRemoteAtEnd YES` (debug builds only) keeps the remote at its
    /// end, where Unlock With This iPhone, Show My Photos, Show My Calendars, Use My Apple Music and My Spotify are, for screenshots.
    private static var startAnchor: UnitPoint? {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "ConnectRemoteAtEnd") ? .bottom : nil
        #else
        nil
        #endif
    }

    private var askField: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField("Ask \(peer.name)", text: $prompt)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: Theme.Size.toolbarItem)
                .glassEffect(.regular, in: Capsule())
                .submitLabel(.send)
                .onSubmit(ask)
            GlassIconButton("arrow.up", label: "Ask", size: Theme.Size.toolbarItem, isProminent: true, action: ask)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func ask() {
        send(.ask(prompt: prompt))
        prompt = ""
    }

    private func send(_ command: RemoteCommand) {
        error = nil
        Task {
            do {
                try await connect.remote.send(command, to: peer.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A titled grid of faces or apps to switch to.
private struct ChoiceGrid: View {
    let title: String
    let systemImage: String
    let choices: [HomePadStatus.Choice]
    let action: (HomePadStatus.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title, systemImage: systemImage)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                ForEach(choices) { choice in
                    Button {
                        action(choice)
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: choice.systemImage).font(.title2)
                            Text(choice.title).font(.callout.weight(.medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
