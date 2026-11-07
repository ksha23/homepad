import HomePadCore
import HomePadUI
import SwiftUI

/// The yellow talk button for a Home Assistant camera with a speaker: the
/// microphone goes to the camera while a finger holds it, like intercom's push
/// to talk. The camera's own sound pauses meanwhile, so the door does not hear
/// itself. Drawn like `GlassIconButton`.
struct HoldToTalkButton: View {
    let audio: CameraAudioControl
    var size: CGFloat = Theme.Size.roundControl
    /// Pressing and letting go, for screens that close themselves when left alone.
    var onInteraction: () -> Void = {}
    @State private var message: String?

    var body: some View {
        Button {} label: {
            Label(audio.isTalking ? "Talking" : "Hold to Talk", systemImage: audio.isTalking ? "waveform" : "mic.fill")
        }
        .buttonStyle(HoldStyle(size: size, onPress: setTalking))
        .symbolEffect(.variableColor.iterative, isActive: audio.isTalking)
        .accessibilityLabel("Hold to Talk")
        .alert("Can't Talk Right Now", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .onDisappear { Task { try? await audio.setTalking(false) } }
    }

    private func setTalking(_ talking: Bool) {
        onInteraction()
        Task {
            do {
                try await audio.setTalking(talking)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// `GlassIconButton`'s look in yellow, reporting the press as it starts and ends.
    private struct HoldStyle: ButtonStyle {
        let size: CGFloat
        let onPress: (Bool) -> Void

        func makeBody(configuration: Configuration) -> some View {
            GlassIconButtonStyle(size: size, tint: .yellow).makeBody(configuration: configuration)
                .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
        }
    }
}
