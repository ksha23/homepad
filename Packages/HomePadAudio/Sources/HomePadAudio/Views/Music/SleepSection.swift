import HomePadCore
import HomePadUI
import SwiftUI

/// Sleep and focus sounds: the person's preset list, a sleep timer from a few
/// choices, and a level for the sound.
struct SleepSection: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SectionHeader("Sleep Sounds", systemImage: "moon.zzz.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.l) {
                ForEach(presets) { preset in presetTile(preset) }
            }
            timerRow
            if media.activeKind == .ambient, media.ambient.sound != nil {
                levelRow
            }
        }
    }

    private var presets: [SleepPreset] {
        services.settings[AudioSettings.sleepPresetIDs].compactMap(SleepPreset.preset)
    }

    private func presetTile(_ preset: SleepPreset) -> some View {
        let isPlaying = media.activeKind == .ambient && media.ambient.presetTitle == preset.title && media.nowPlaying?.isPlaying == true
        return Button {
            Task {
                await media.perform {
                    if isPlaying { await media.pause() } else { try media.play(preset) }
                }
            }
        } label: {
            GlassTile(isHighlighted: isPlaying, tint: .indigo) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Image(systemName: isPlaying ? "pause.fill" : preset.sound.systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: Theme.Spacing.m)
                    Text(preset.title).font(.title3.bold())
                    Text(preset.sound.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(height: 170)
        }
        .buttonStyle(.plain)
    }

    private var timerRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Sleep Timer", systemImage: "timer")
            HStack(spacing: Theme.Spacing.s) {
                ForEach(SleepTimer.choices, id: \.self) { minutes in
                    GlassCapsuleButton(SleepTimer.label(minutes: minutes), size: .regular) {
                        minutes == 0 ? media.sleepTimer.cancel() : media.sleepTimer.start(minutes: minutes)
                    }
                    .disabled(media.nowPlaying == nil && minutes > 0)
                }
            }
            if media.sleepTimer.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = media.sleepTimer.remaining(at: context.date) ?? 0
                    Text("Stops in \(Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var levelRow: some View {
        @Bindable var ambient = media.ambient
        return HStack(spacing: Theme.Spacing.m) {
            VolumeRow {
                Slider(value: Binding(get: { ambient.volume }, set: { ambient.setVolume($0) }), in: 0...1)
                    .accessibilityLabel("Sleep sound volume")
            }
            .frame(maxWidth: 420)
            GlassCapsuleButton("Stop", systemImage: "stop.fill", size: .regular) { media.stopAll() }
        }
    }
}
