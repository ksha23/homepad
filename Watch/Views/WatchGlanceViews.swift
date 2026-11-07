import SwiftUI

/// Timers running on HomePads.
struct WatchTimersView: View {
    @Environment(WatchLink.self) private var link

    var body: some View {
        List {
            if link.timers.isEmpty {
                Text("No timers").foregroundStyle(.secondary)
            }
            ForEach(link.timers) { timer in
                VStack(alignment: .leading) {
                    Group {
                        if timer.isRunning, let end = timer.end, end > .now {
                            Text(timerInterval: Date.now...end, countsDown: true)
                        } else {
                            Text(Duration.seconds(timer.remaining).formatted(.time(pattern: .minuteSecond)))
                        }
                    }
                    .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    Text("\(timer.label), \(timer.room)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Timers")
        .refreshable { link.refresh() }
        .onAppear { link.refresh() }
    }
}

/// One tap per scene.
struct WatchScenesView: View {
    @Environment(WatchLink.self) private var link

    var body: some View {
        List {
            if link.scenes.isEmpty {
                Text(link.message ?? "No scenes").foregroundStyle(.secondary)
            }
            ForEach(link.scenes) { scene in
                Button {
                    link.runScene(scene)
                } label: {
                    Label(scene.name, systemImage: scene.symbol)
                }
            }
        }
        .navigationTitle("Scenes")
        .onAppear { link.refresh() }
    }
}
