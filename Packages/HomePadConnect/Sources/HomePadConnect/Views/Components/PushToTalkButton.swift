import HomePadCore
import HomePadUI
import SwiftUI

/// A large round press-and-hold button: recording starts on touch down and
/// ends on release, with a live level ring. It is the intercom's signature
/// control, so it stays in this module.
struct PushToTalkButton: View {
    let isActive: Bool
    /// Microphone level 0...1 while active.
    let level: Double
    var diameter: CGFloat = 220
    var systemImage = "waveform"
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.ultraThinMaterial))
            // White on the accent while recording, the appearance's primary
            // color on the material at rest.
            Circle()
                .strokeBorder(isActive ? Color.white.opacity(0.9) : Color.primary.opacity(0.2), lineWidth: isActive ? 4 + level * 18 : 1)
                .animation(.smooth(duration: 0.15), value: level)
            Image(systemName: isActive ? "waveform" : systemImage)
                .font(.system(size: diameter * 0.32, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: isActive)
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.smooth(duration: 0.2), value: isPressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onPress()
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
        .accessibilityLabel(isActive ? "Release to send" : "Hold to talk")
        .accessibilityAddTraits(.isButton)
        .nightModeAware()
    }
}
