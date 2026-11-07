import SwiftUI

/// A ring split into equal segments that fill as steps complete, like the
/// Face ID enrollment ring. Use it for multi-step setup flows.
///
///     SegmentedProgressRing(segments: 4, completed: done, current: progress)
///         .frame(width: 320, height: 320)
public struct SegmentedProgressRing: View {
    private let segments: Int
    private let completed: Int
    private let current: Double
    private let lineWidth: CGFloat
    private let tint: Color

    /// - Parameters:
    ///   - segments: Number of steps.
    ///   - completed: Steps already done.
    ///   - current: Progress of the step in progress, 0 to 1.
    ///   - lineWidth: Stroke width of the ring.
    ///   - tint: Fill color. Green, like Face ID, by default.
    public init(segments: Int, completed: Int, current: Double = 0, lineWidth: CGFloat = 10, tint: Color = .green) {
        self.segments = segments
        self.completed = completed
        self.current = current
        self.lineWidth = lineWidth
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            ForEach(0..<max(segments, 1), id: \.self) { index in
                let gap = 0.012
                let start = Double(index) / Double(max(segments, 1)) + gap / 2
                let end = Double(index + 1) / Double(max(segments, 1)) - gap / 2
                Circle()
                    .trim(from: start, to: end)
                    .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: start, to: start + (end - start) * fill(for: index))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .animation(.smooth(duration: 0.4), value: completed)
        .animation(.smooth(duration: 0.4), value: current)
        .accessibilityElement()
        .accessibilityLabel("\(completed) of \(segments) steps done")
    }

    private func fill(for index: Int) -> Double {
        if index < completed { return 1 }
        if index == completed { return min(max(current, 0), 1) }
        return 0
    }
}
