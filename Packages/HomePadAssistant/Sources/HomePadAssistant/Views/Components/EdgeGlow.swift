import HomePadCore
import HomePadUI
import SwiftUI

/// A glowing, slowly rotating rainbow around the edge of the screen, like
/// Siri's edge light. Brighter while listening, swirling while thinking.
/// Specific to the assistant, so it stays in this module.
struct EdgeGlow: View {
    var phase: AssistantPhase
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayCondition) private var displayCondition

    var body: some View {
        // Still while the display sleeps: an overlay left up (a question
        // waiting for an answer) would otherwise redraw every frame unseen.
        TimelineView(.animation(paused: reduceMotion || displayCondition == .sleeping)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let motion = AssistantPalette.motion(for: phase)
            let width = 10 + motion.strength * 14 + (phase == .listening ? level * 30 : 0)
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: AssistantPalette.glow, center: .center, angle: .degrees((time * motion.speed).truncatingRemainder(dividingBy: 360))),
                    lineWidth: width
                )
                .blur(radius: width * 0.9)
                .opacity(0.4 + motion.strength * 0.6)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.5), value: phase)
        .accessibilityHidden(true)
    }
}
