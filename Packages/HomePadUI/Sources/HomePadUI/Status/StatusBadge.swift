import HomePadCore
import SwiftUI

/// A small glass capsule with a colored dot and an uppercase word, like
/// HomeView's "LIVE" badge on camera views. Set `pulses` for something
/// happening right now, such as recording.
///
///     StatusBadge.live
///     StatusBadge("Scanning", color: .green)
///     StatusBadge("Security Camera On", color: .red, pulses: true)
public struct StatusBadge: View {
    private let text: String
    private let color: Color
    private let pulses: Bool
    @Environment(\.allowsContinuousMotion) private var allowsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - text: One or two words. Drawn uppercase.
    ///   - color: Color of the dot.
    ///   - pulses: Slowly fades the dot in and out.
    public init(_ text: String, color: Color, pulses: Bool = false) {
        self.text = text
        self.color = color
        self.pulses = pulses
    }

    /// The red "LIVE" badge for camera streams.
    public static var live: StatusBadge { StatusBadge("Live", color: .red) }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            dot
            // Subheadline in capitals is as tall as body text in lower case,
            // so the badge reads from arm's length without crowding a camera view.
            Text(text)
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// The dot. A pulsing one fades at 12 frames a second, enough for a slow
    /// fade on a dot this small, and holds still while the display is dimmed or
    /// asleep. The Security Camera badge pulses on every screen for as long as
    /// it watches, and a `repeatForever` animation redrew the screen at 60.
    private var dot: some View {
        let isPulsing = pulses && allowsMotion && !reduceMotion
        return TimelineView(.animation(minimumInterval: 1 / 12, paused: !isPulsing)) { context in
            Circle()
                .fill(color)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .opacity(isPulsing ? Self.pulse(at: context.date) : 1)
        }
        .frame(width: Self.dotSize, height: Self.dotSize)
    }

    /// The dot's diameter, about the height of the capitals beside it.
    private static let dotSize: CGFloat = 11

    /// From 1 down to 0.35 and back every two seconds.
    static func pulse(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate * .pi
        return 0.675 + 0.325 * cos(phase)
    }
}
