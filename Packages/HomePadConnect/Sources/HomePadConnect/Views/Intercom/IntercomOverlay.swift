import HomePadCore
import HomePadUI
import SwiftUI

/// "Intercom from Kitchen": shown above everything while a message plays,
/// or with a Play button when it arrived during quiet hours.
struct IntercomOverlay: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        VStack {
            if let record = connect.intercom.current, record.direction == .received {
                GlassBanner(
                    systemImage: "waveform",
                    tint: .green,
                    title: "Intercom from \(record.peerName)",
                    subtitle: record.text ?? (connect.intercom.isPlaying ? "Playing" : "Voice message")
                ) {
                    EmptyView()
                } actions: {
                    if !connect.intercom.isPlaying {
                        GlassIconButton("play.fill", label: "Play") { connect.intercom.play(record) }
                    }
                    CloseButton("Dismiss") { connect.intercom.dismissCurrent() }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.smooth, value: connect.intercom.current)
    }
}

/// The "Intercom, Everywhere" tile from HomeView's Home Modular face, as a
/// small widget and a Control Center tile. Hold it to talk to every room.
struct IntercomTile: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        GlassTile(isHighlighted: connect.intercom.isRecording, tint: .green) {
            // Stacked in a square tile, side by side in a short wide one (Control Center).
            ViewThatFits(in: .vertical) {
                VStack(spacing: Theme.Spacing.s) {
                    symbol
                    labels(alignment: .center)
                }
                HStack(spacing: Theme.Spacing.m) {
                    symbol
                    labels(alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !connect.intercom.isRecording else { return }
                    Task { await connect.intercom.startRecording(to: .everyone) }
                }
                .onEnded { _ in Task { await connect.intercom.finishRecording() } }
        )
        .accessibilityLabel("Intercom Everywhere. Hold to talk.")
    }

    private var symbol: some View {
        Image(systemName: "waveform")
            .font(.system(size: 44, weight: .semibold))
            .symbolEffect(.variableColor.iterative, isActive: connect.intercom.isRecording)
    }

    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("Intercom").font(.title3.bold())
            Text(connect.intercom.isRecording ? "Talking" : "Everywhere")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}
