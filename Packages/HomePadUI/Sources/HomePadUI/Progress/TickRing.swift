import SwiftUI

/// A ring of tick marks that lights up in proportion to `progress`, like
/// HomeView's timer face. Lit ticks run clockwise from the top. Use it for
/// countdowns and levels (timers, cooking progress, battery).
///
///     TickRing(progress: timer.progress(at: now))
///     TickRing(progress: 0.4, tint: .green, tickCount: 20, tickWidthRatio: 0.07, tickLengthRatio: 0.24)
public struct TickRing: View {
    private let progress: Double
    private let tint: Color
    private let tickCount: Int
    private let tickWidthRatio: CGFloat
    private let tickLengthRatio: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - progress: 0 (no ticks lit) to 1 (all lit).
    ///   - tint: Color of lit ticks. Unlit ticks use a faint version, a little
    ///     stronger in Light so they still show on white. Orange, like Apple's timers, by default.
    ///   - tickCount: Number of ticks around the ring.
    ///   - tickWidthRatio: Tick thickness relative to the ring's diameter.
    ///   - tickLengthRatio: Tick length relative to the ring's diameter. Small rings need longer ticks.
    public init(
        progress: Double, tint: Color = .orange, tickCount: Int = 60,
        tickWidthRatio: CGFloat = 0.011, tickLengthRatio: CGFloat = 0.075
    ) {
        self.progress = progress
        self.tint = tint
        self.tickCount = tickCount
        self.tickWidthRatio = tickWidthRatio
        self.tickLengthRatio = tickLengthRatio
    }

    public var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let tickLength = diameter * tickLengthRatio
            let tickWidth = max(2, diameter * tickWidthRatio)
            let lit = Int((min(max(progress, 0), 1) * Double(tickCount)).rounded(.up))
            ZStack {
                ForEach(0..<tickCount, id: \.self) { index in
                    Capsule()
                        .fill(index < lit ? tint : tint.opacity(colorScheme == .light ? 0.3 : 0.18))
                        .frame(width: tickWidth, height: tickLength)
                        .offset(y: -(diameter - tickLength) / 2)
                        .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.smooth(duration: 0.4), value: Int(progress * Double(tickCount)))
        .accessibilityHidden(true)
    }
}
