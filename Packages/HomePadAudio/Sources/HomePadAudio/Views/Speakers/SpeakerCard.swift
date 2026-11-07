import HomePadCore
import HomePadUI
import SwiftUI

/// One Music Assistant speaker or group: what it plays, its multi-room group, its
/// volume, and a button to play there.
struct SpeakerCard: View {
    let player: MusicAssistantPlayer
    @Environment(AudioMediaService.self) private var media
    @State private var volume: Double = 0.4
    @State private var isEditingVolume = false

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    Image(systemName: player.model.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(player.isPlaying ? Theme.tint(for: .mediaPlayer) : .secondary)
                        .symbolEffect(.pulse, isActive: player.isPlaying)
                    Spacer()
                    if isTarget {
                        GlassPill("Playing Here", systemImage: "checkmark")
                    }
                }
                Text(player.name).font(.title2.bold()).lineLimit(1)
                Text(statusLine).font(.headline).foregroundStyle(.secondary).lineLimit(1)
                if let group = groupLine {
                    Label(group, systemImage: "link").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.m) {
                    VolumeRow {
                        Slider(value: $volume, in: 0...1) { editing in
                            isEditingVolume = editing
                            if !editing { Task { await media.perform { try await media.musicAssistant.setVolume(volume, on: player.id) } } }
                        }
                        .accessibilityLabel("\(player.name) volume")
                    }
                    if !isTarget {
                        GlassCapsuleButton("Play Here", size: .regular) {
                            Task { await media.perform { try await media.musicAssistant.playOn([player.id]) } }
                        }
                    }
                }
            }
        }
        .frame(height: 240)
        .onAppear { volume = player.volume ?? volume }
        .onChange(of: player.volume) { _, new in
            if !isEditingVolume, let new { volume = new }
        }
    }

    private var isTarget: Bool {
        media.musicSource == .musicAssistant && media.musicAssistant.targetPlayer?.id == player.id
    }

    private var statusLine: String {
        if !player.isReachable { return "Not Responding" }
        guard let line = player.nowPlayingLine else { return "Idle" }
        return player.isPlaying ? line : "Paused · \(line)"
    }

    private var groupLine: String? {
        let members = media.musicAssistant.groupMembers(of: player).map(\.name)
        guard !members.isEmpty else { return nil }
        return player.isGroupPlayer ? members.formatted(.list(type: .and)) : "With \(members.formatted(.list(type: .and)))"
    }
}
