import HomePadCore
import HomePadUI
import SwiftUI

/// The companion's Home tab: scenes and every timer running on a HomePad.
struct CompanionHomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect
    @State private var runningSceneID: String?

    /// This device's own smart home when one is set up, else scenes reported by HomePads.
    private var scenes: [HomeScene] {
        let local = services.smartHome.scenes.filter { $0.backend != .demo }
        return local.isEmpty ? (connect.remote.scenes.isEmpty ? services.smartHome.scenes : connect.remote.scenes) : local
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SectionHeader("Scenes", systemImage: "sparkles")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                    ForEach(scenes) { scene in
                        Button { run(scene) } label: {
                            GlassTile(isHighlighted: runningSceneID == scene.id, tint: .orange) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                    Image(systemName: scene.systemImage).font(.title).foregroundStyle(.orange)
                                    Spacer(minLength: 0)
                                    Text(scene.name).font(.headline).lineLimit(2)
                                    Text("Scene").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(height: 130)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TimersSection(timers: connect.remote.timers.map(\.timer), target: nil) { timer in
                    connect.remote.timers.first { $0.timer.id == timer.id }?.homePad
                }
            }
            .padding(Theme.Spacing.l)
        }
        .navigationTitle("Home")
        .task {
            while !Task.isCancelled {
                await connect.remote.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func run(_ scene: HomeScene) {
        runningSceneID = scene.id
        Task {
            if services.smartHome.scenes.contains(where: { $0.id == scene.id }) {
                try? await services.smartHome.activateScene(scene.id)
            } else {
                try? await connect.remote.send(.runScene(id: scene.id))
            }
            try? await Task.sleep(for: .seconds(1))
            runningSceneID = nil
        }
    }
}
