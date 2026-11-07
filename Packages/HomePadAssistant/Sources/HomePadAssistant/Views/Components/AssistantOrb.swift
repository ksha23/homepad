import HomePadCore
import SwiftUI

/// A glass orb with a moving band of light and a soft rainbow rim, like the
/// Siri orb on HomeView. It breathes with the microphone level while listening
/// and swirls while thinking. It is the assistant's signature, so it stays
/// in this module.
struct AssistantOrb: View {
    var phase: AssistantPhase
    /// Microphone level 0 to 1, used while listening.
    var level: Double = 0
    var size: CGFloat = 88

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayCondition) private var displayCondition

    var body: some View {
        // Still while the display sleeps: an overlay left up (a question
        // waiting for an answer) would otherwise redraw every frame unseen.
        TimelineView(.animation(paused: reduceMotion || displayCondition == .sleeping)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let motion = AssistantPalette.motion(for: phase)
            let breath = phase == .listening ? level * 0.6 : (sin(time * 2) + 1) * 0.04
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.10), .black.opacity(0.75)],
                                         center: .center, startRadius: 0, endRadius: size * 0.6))
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.78, height: size * (0.07 + breath * 0.25))
                    .blur(radius: size * 0.025)
                    .rotationEffect(.degrees(sin(time * motion.speed / 60) * 10))
                    .offset(y: sin(time * 1.1) * size * 0.04)
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: AssistantPalette.glow, center: .center, angle: .degrees((time * motion.speed).truncatingRemainder(dividingBy: 360))),
                        lineWidth: size * 0.03
                    )
                    .opacity(0.35 + motion.strength * 0.5)
                    .blur(radius: 1)
            }
            .frame(width: size, height: size)
            .scaleEffect(1 + breath * 0.25)
            .glassEffect(.clear, in: Circle())
            .shadow(color: AssistantPalette.glow[2].opacity(0.35 * motion.strength), radius: size * 0.3)
        }
        .accessibilityHidden(true)
    }
}
