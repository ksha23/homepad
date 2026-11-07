import SwiftUI

/// A HomeView-style progress bar with elapsed and remaining time. Drag to seek.
/// Live streams show a "LIVE" badge instead.
struct PlaybackScrubber: View {
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    var isLive: Bool
    var onSeek: (TimeInterval) -> Void

    @State private var dragProgress: Double?
    /// Where a drag let go, held until the player reports a position near it. On letting go the
    /// bar went back to the last reading, from before the seek, until the next one came. Apple's
    /// player also counts on for about a third of a second after a seek to the HomePods, then
    /// starts again from the seek (measured on the iPad, Nov 2026), which the hold hides too.
    @State private var seekProgress: Double?

    var body: some View {
        if isLive {
            liveBadge
        } else {
            VStack(spacing: 8) {
                bar
                HStack {
                    Text(Self.format(currentTime))
                    Spacer()
                    Text("-" + Self.format(max(0, (duration ?? 0) - currentTime)))
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var progress: Double {
        if let dragProgress { return dragProgress }
        if let seekProgress { return seekProgress }
        guard let duration, duration > 0, let elapsed else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    private var currentTime: TimeInterval { progress * (duration ?? 0) }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: proxy.size.width * progress)
            }
            .frame(height: dragProgress == nil ? 8 : 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in dragProgress = min(1, max(0, value.location.x / proxy.size.width)) }
                .onEnded { _ in
                    if let dragProgress, let duration {
                        seekProgress = dragProgress
                        onSeek(dragProgress * duration)
                    }
                    dragProgress = nil
                })
            .animation(.smooth(duration: 0.2), value: dragProgress == nil)
        }
        .frame(height: 24)
        .onChange(of: elapsed) { _, reading in
            guard let seekProgress, let reading, let duration, duration > 0 else { return }
            if abs(reading - seekProgress * duration) <= Self.seekLanding { self.seekProgress = nil }
        }
        // A player that never reports the new position does not hold the bar for good.
        .task(id: seekProgress) {
            guard seekProgress != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            seekProgress = nil
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.format(currentTime)) of \(Self.format(duration ?? 0))")
    }

    private var liveBadge: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text("LIVE").font(.callout.weight(.bold))
            Capsule().fill(.white.opacity(0.25)).frame(height: 8)
        }
        .foregroundStyle(.secondary)
        .frame(height: 44)
    }

    /// How close a reported position has to be to the seek, in seconds, to show it again.
    static let seekLanding: TimeInterval = 1

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
