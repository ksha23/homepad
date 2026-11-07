import SwiftUI

extension View {
    /// Watches a HomePad's music while this view is on screen and the app is in
    /// the foreground, so the HomePad pushes every change only while someone looks.
    func watchesMusic(of peerID: String) -> some View {
        modifier(MusicWatchModifier(peerID: peerID))
    }
}

private struct MusicWatchModifier: ViewModifier {
    @Environment(ConnectRuntime.self) private var connect
    @Environment(\.scenePhase) private var scenePhase
    let peerID: String
    @State private var isVisible = false
    @State private var isWatching = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                update()
            }
            .onDisappear {
                isVisible = false
                update()
            }
            .onChange(of: scenePhase) { update() }
    }

    private func update() {
        let shouldWatch = isVisible && scenePhase != .background
        guard shouldWatch != isWatching else { return }
        isWatching = shouldWatch
        if shouldWatch {
            connect.music.watch(peerID)
        } else {
            connect.music.stopWatching(peerID)
        }
    }
}
