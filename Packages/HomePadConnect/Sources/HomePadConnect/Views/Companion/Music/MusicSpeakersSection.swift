import HomePadCore
import HomePadUI
import SwiftUI

/// The HomePad's outputs, checked where the music plays. Tapping one moves the
/// music there: a speaker HomePad controls (HomePods through Music Assistant,
/// Sonos) takes it over, and the iPad's own route brings it back.
struct MusicSpeakersSection: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    let outputs: [RemoteMediaStatus.Output]
    @State private var selectingID: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Play On", systemImage: "hifispeaker.2.fill")
            VStack(spacing: 0) {
                ForEach(outputs) { output in
                    row(output)
                    if output.id != outputs.last?.id {
                        Divider().padding(.leading, Theme.Spacing.m + Theme.Size.minTapTarget)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            Text("To add AirPlay speakers, use AirPlay on the HomePad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ output: RemoteMediaStatus.Output) -> some View {
        Button {
            select(output)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: Self.symbol(for: output.outputKind))
                    .font(.title3)
                    .frame(width: Theme.Size.minTapTarget)
                VStack(alignment: .leading, spacing: 2) {
                    Text(output.name).font(.headline).lineLimit(1)
                    Text(detail(output)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selectingID == output.id {
                    ProgressView()
                } else if output.isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Playing here")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectingID != nil)
    }

    /// The kind, and "In Use" for a speaker busy with music of its own.
    private func detail(_ output: RemoteMediaStatus.Output) -> String {
        let kind = Self.kindName(output.outputKind)
        return output.isActive && !output.isCurrent ? "\(kind) · In Use" : kind
    }

    private func select(_ output: RemoteMediaStatus.Output) {
        error = nil
        selectingID = output.id
        Task {
            do {
                try await connect.music.send(.selectOutput(id: output.id), to: peer.id)
            } catch {
                self.error = error.localizedDescription
            }
            selectingID = nil
        }
    }

    static func symbol(for kind: AudioOutputKind?) -> String {
        switch kind {
        case .builtInSpeaker: "ipad.landscape"
        case .airPlay: "airplayaudio"
        case .bluetooth: "headphones"
        case .wired: "cable.connector"
        case .homeAssistantPlayer, nil: "hifispeaker.fill"
        }
    }

    static func kindName(_ kind: AudioOutputKind?) -> String {
        switch kind {
        case .builtInSpeaker: "Built-in Speaker"
        case .airPlay: "AirPlay"
        case .bluetooth: "Bluetooth"
        case .wired: "Wired"
        case .homeAssistantPlayer: "Home Assistant"
        case nil: "Speaker"
        }
    }
}
