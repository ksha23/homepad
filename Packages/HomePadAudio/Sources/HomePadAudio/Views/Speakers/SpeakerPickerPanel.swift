import HomePadCore
import HomePadUI
import SwiftUI

/// "Play On": where music plays, as a glass panel over the current screen, the
/// way Control Center's AirPlay card works. With Music Assistant, check one
/// speaker or several for multi-room and set each volume. With This iPad, use
/// the system AirPlay picker, and see what plays elsewhere in the house.
/// Close with the close button, a tap outside or a swipe down.
struct SpeakerPickerPanel: View {
    let onClose: () -> Void
    @Environment(AudioMediaService.self) private var media
    @State private var selection: [String] = []
    @State private var isApplying = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack {
                        Text("Play On").font(.title.bold())
                        Spacer()
                        CloseButton(action: onClose)
                    }
                    switch media.musicSource {
                    case .musicAssistant: musicAssistantPicker
                    case .spotify: SpotifyDevicePicker()
                    case .thisIPad: thisIPadPicker
                    }
                }
                .frame(width: 500)
            }
            .padding(Theme.Spacing.l)
            .padding(.top, Theme.Size.tapTarget)
            .swipeDownToDismiss(style: .panel, onDismiss: onClose)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .onAppear(perform: loadSelection)
    }

    // MARK: Music Assistant

    private var musicAssistantPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Check several speakers to play in many rooms at once.")
                .font(.tileDetail)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(media.musicAssistant.players) { player in
                        PickerSpeakerRow(player: player, isSelected: selection.contains(player.id)) { toggle(player.id) }
                    }
                }
            }
            .frame(maxHeight: 460)
            .scrollBounceBehavior(.basedOnSize)
            if let error = media.lastError {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            GlassCapsuleButton(applyTitle, systemImage: "play.fill", isProminent: true, tint: .pink) {
                Task {
                    isApplying = true
                    await media.perform { try await media.musicAssistant.playOn(selection) }
                    isApplying = false
                    if media.lastError == nil { onClose() }
                }
            }
            .disabled(selection.isEmpty || isApplying)
            .frame(maxWidth: .infinity)
        }
    }

    private var applyTitle: String {
        switch selection.count {
        case 0: "Choose a Speaker"
        case 1: "Play on \(media.musicAssistant.player(selection[0])?.name ?? "Speaker")"
        default: "Play on \(selection.count) Speakers"
        }
    }

    private func loadSelection() {
        guard let target = media.musicAssistant.targetPlayer else { return }
        selection = [target.id] + media.musicAssistant.groupMembers(of: target).map(\.id)
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) { selection.remove(at: index) } else { selection.append(id) }
    }

    // MARK: This iPad

    private var thisIPadPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AirPlayButton(size: Theme.Size.roundControl, isGlass: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This iPad plays on").font(.tileDetail).foregroundStyle(.secondary)
                    Text(media.currentRouteName).font(.title2.bold())
                }
            }
            Text("Tap AirPlay and check several HomePods to play in many rooms.")
                .font(.tileDetail)
                .foregroundStyle(.secondary)
            let elsewhere = media.elsewhereInTheHouse
            if !elsewhere.isEmpty {
                SectionHeader("Elsewhere in the House")
                ForEach(elsewhere) { player in
                    Label("\(player.name): \(player.nowPlayingLine ?? "Playing")", systemImage: player.model.systemImage)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            if media.canChooseMusicSource {
                GlassCapsuleButton("Use Music Assistant Speakers", systemImage: "hifispeaker.2.fill") {
                    media.setMusicSource(.musicAssistant)
                    loadSelection()
                }
            }
        }
    }
}

/// One speaker in the Play On panel: a checkmark, its name and status, and its volume.
private struct PickerSpeakerRow: View {
    let player: MusicAssistantPlayer
    let isSelected: Bool
    let toggle: () -> Void
    @Environment(AudioMediaService.self) private var media
    @State private var volume: Double = 0.4

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: toggle) {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: player.model.systemImage)
                        .font(.title2)
                        .foregroundStyle(player.isPlaying ? Theme.tint(for: .mediaPlayer) : .secondary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(player.name).font(.tileTitle)
                        Text(player.nowPlayingLine ?? (player.isGroupPlayer ? "Group" : "Idle"))
                            .font(.tileDetail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if isSelected {
                VolumeRow {
                    Slider(value: $volume, in: 0...1) { editing in
                        if !editing { Task { await media.perform { try await media.musicAssistant.setVolume(volume, on: player.id) } } }
                    }
                    .accessibilityLabel("\(player.name) volume")
                }
                .padding(.leading, 36 + Theme.Spacing.m)
            }
        }
        .padding(Theme.Spacing.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.primary.opacity(isSelected ? 0.08 : 0)))
        .animation(Theme.Motion.standard, value: isSelected)
        .onAppear { volume = player.volume ?? volume }
    }
}
