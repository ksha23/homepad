import SwiftUI

/// Redraws its content four times a second with the current time, for
/// countdowns and elapsed time. Stops redrawing when nothing is running.
///
///     LiveTime(isActive: timer.isRunning) { now in
///         Text(timer.remaining(at: now), format: .timer)
///     }
public struct LiveTime<Content: View>: View {
    private let isActive: Bool
    private let content: (Date) -> Content

    /// - Parameters:
    ///   - isActive: Redraws only while true.
    ///   - content: Draws the view for a moment in time.
    public init(isActive: Bool = true, @ViewBuilder content: @escaping (Date) -> Content) {
        self.isActive = isActive
        self.content = content
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: isActive ? 0.25 : 3600)) { context in
            content(context.date)
        }
    }
}
