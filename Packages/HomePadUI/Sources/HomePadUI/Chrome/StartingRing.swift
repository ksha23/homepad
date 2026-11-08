import HomePadCore
import SwiftUI

/// A short arc that turns around a round view while what it stands for gets
/// ready, such as face recognition after launch around the people button.
/// Where continuous motion is off (dimmed or night display, thumbnails) or
/// with Reduce Motion, the arc stays still.
///
///     AvatarView(member: member).startingRing(presence.isRecognitionStarting)
public struct StartingRing: View {
    private let lineWidth: CGFloat
    @Environment(\.allowsContinuousMotion) private var allowsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter lineWidth: Width of the arc in points.
    public init(lineWidth: CGFloat = 3) {
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let turns = allowsMotion && !reduceMotion
        TimelineView(.animation(paused: !turns)) { context in
            // One turn every 1.2 s, starting from the top.
            let angle = turns ? context.date.timeIntervalSinceReferenceDate / 1.2 * 360 : 0
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360) - 90))
        }
        // Just outside the avatar's own white edge.
        .padding(-(lineWidth + 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// Draws a `StartingRing` around this round view while `isStarting` is true.
    func startingRing(_ isStarting: Bool) -> some View {
        overlay {
            if isStarting { StartingRing() }
        }
    }
}
