import HomePadCore
import HomePadUI
import SwiftUI

/// Set up and run a timelapse, and play back what it captured.
struct TimelapseView: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var showingPlayer = false

    var body: some View {
        let timelapse = lab.timelapse
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Form {
                Section {
                    Picker("Every", selection: services.settings.binding(CameraLabSettings.timelapseInterval)) {
                        ForEach(TimelapseInterval.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .disabled(timelapse.isRunning)
                    TextField("Album", text: services.settings.binding(CameraLabSettings.timelapseAlbum))
                        .disabled(timelapse.isRunning)
                } header: {
                    Text("Interval")
                } footer: {
                    Text("\(timelapse.interval.suggestion) Frames go to the \(timelapse.albumName) album in Photos.")
                }
                Section {
                    if timelapse.isRunning {
                        LabeledContent("Frames Today", value: "\(timelapse.framesThisSession)")
                        if let next = timelapse.nextShotAt {
                            LabeledContent("Next Frame") { Text(next, style: .timer).monospacedDigit() }
                        }
                    }
                    if let problem = timelapse.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Button(timelapse.isRunning ? "Stop Timelapse" : "Start Timelapse",
                           systemImage: timelapse.isRunning ? "stop.fill" : "record.circle") {
                        if timelapse.isRunning { timelapse.stop() } else { Task { await timelapse.start() } }
                    }
                    .tint(timelapse.isRunning ? .red : .yellow)
                    Button("Play Timelapse", systemImage: "play.rectangle") { showingPlayer = true }
                } footer: {
                    Text(timelapse.interval.keepsCameraBetweenShots
                         ? "At this interval the camera stays on, so presence sensing pauses while the timelapse runs."
                         : "Between frames the camera goes back to presence sensing.")
                }
            }
            .scrollContentBackground(.hidden)
            .frame(width: 440)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .sheet(isPresented: $showingPlayer) {
            TimelapsePlayerView(album: timelapse.albumName)
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let timelapse = lab.timelapse
        if timelapse.isRunning, lab.broker.isHeld(by: TimelapseController.owner) {
            CameraViewport().aspectRatio(4 / 3, contentMode: .fit)
        } else if let frame = timelapse.lastFrame {
            Image(uiImage: frame)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .overlay(alignment: .topLeading) {
                    StatusBadge("Last Frame", color: .yellow).padding(Theme.Spacing.m)
                }
                .nightModeAware()
        } else {
            GlassTile {
                EmptyStateView(
                    "Watch Something Change",
                    message: "Point the back camera at a plant, the pantry or a window, pick an interval, and start. HomePad saves a frame each time.",
                    systemImage: "timelapse"
                )
            }
            .aspectRatio(4 / 3, contentMode: .fit)
        }
    }
}

/// Plays the album's frames in order, like a video.
struct TimelapsePlayerView: View {
    let album: String
    @State private var player = TimelapsePlayerModel()

    var body: some View {
        SheetScreen(album) {
            VStack(spacing: Theme.Spacing.l) {
                if player.assets.isEmpty {
                    EmptyStateView("No Frames Yet", message: "Start a timelapse and frames appear here as they are saved to \(album).", systemImage: "photo.stack")
                } else {
                    Group {
                        if let image = player.image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    controls
                }
            }
            .padding([.horizontal, .bottom], Theme.Spacing.l)
        }
        .task { await player.load(album: album) }
        .onDisappear { player.pause() }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.l) {
            GlassIconButton(player.isPlaying ? "pause.fill" : "play.fill",
                            label: player.isPlaying ? "Pause" : "Play", tint: .yellow) {
                player.togglePlayback()
            }
            VStack(alignment: .leading) {
                Slider(value: Binding(get: { Double(player.index) }, set: { player.index = Int($0.rounded()) }),
                       in: 0...Double(max(1, player.assets.count - 1)))
                HStack {
                    Text("Frame \(player.index + 1) of \(player.assets.count)")
                    Spacer()
                    if let date = player.currentDate { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Picker("Speed", selection: $player.speed) {
                ForEach(TimelapsePlayerModel.speeds, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(width: 220)
        }
    }
}
