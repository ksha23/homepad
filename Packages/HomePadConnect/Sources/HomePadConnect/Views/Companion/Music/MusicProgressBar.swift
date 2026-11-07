import HomePadCore
import HomePadUI
import SwiftUI

/// Progress through what plays on a HomePad, moved on locally from the last
/// status once a second while it plays. A scrubber when the HomePad can seek,
/// a plain bar when it cannot, and a Live badge for a stream with no end.
///
/// The scrubber is a bar like Apple Music's rather than a `Slider`. A finger
/// anywhere on it moves the position by how far the finger travels, and lifting
/// it seeks once. The Slider only took drags that began on its small thumb, so
/// a drag that began beside the thumb did nothing, and it wrote its value back
/// as the bar moved on by itself, which sent seeks nobody made.
struct MusicProgressBar: View {
    let track: RemoteMediaStatus.Track
    let receivedAt: Date
    let canSeek: Bool
    let onSeek: (Double) -> Void
    /// The position under the finger, kept after release until a status shows the HomePad there.
    @State private var scrubbing: Double?
    /// The position the drag began at. Nil while no finger is on the bar.
    @State private var dragStart: Double?
    /// When the seek went, so a HomePad that never reports the new position does not hold the bar for good.
    @State private var seekSentAt: Date?
    /// True while a finger is on the bar. It goes false by itself when the system takes the touch away.
    @GestureState private var isTouching = false

    var body: some View {
        if let duration = track.duration, duration > 0 {
            // One schedule from when the status came, so the bar moves on in step with it.
            TimelineView(.periodic(from: receivedAt, by: 1)) { context in
                let position = min(duration, scrubbing ?? track.position(after: context.date.timeIntervalSince(receivedAt)) ?? 0)
                VStack(spacing: Theme.Spacing.xs) {
                    if canSeek {
                        scrubber(position: position, duration: duration)
                    } else {
                        ProgressView(value: position, total: duration)
                            .tint(.primary)
                            .accessibilityLabel("Position")
                    }
                    HStack {
                        Text(Self.time(position))
                        Spacer()
                        Text("-" + Self.time(duration - position))
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: receivedAt) { releaseScrubbing(duration: duration) }
            .onChange(of: isTouching) { _, touching in
                if !touching { dropCancelledDrag() }
            }
        } else if track.isPlaying {
            StatusBadge.live
        }
    }

    /// The bar, thicker while a finger is on it. Its touch area is a full tap target high.
    private func scrubber(position: Double, duration: Double) -> some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let played = min(1, max(0, position / duration))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.2))
                Capsule()
                    .fill(.primary)
                    .frame(width: width * played)
            }
            .frame(height: dragStart == nil ? Self.barHeight : Self.touchedBarHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(from: position, duration: duration, width: width))
        }
        .frame(height: Theme.Size.minTapTarget)
        .animation(Theme.Motion.standard, value: dragStart == nil)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(Self.time(position))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? Self.accessibilityStep : -Self.accessibilityStep
            seek(to: min(duration, max(0, position + step)), from: position)
        }
    }

    /// Moves the position by the finger's travel across the bar, the whole bar
    /// being the whole song, and seeks when the finger lifts.
    private func drag(from position: Double, duration: Double, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                let start = dragStart ?? position
                if dragStart == nil {
                    dragStart = start
                    RemoteMediaTrace.trace.log("phone drag began at \(Int(start)) s")
                }
                let moved = Double(value.translation.width / width) * duration
                scrubbing = min(duration, max(0, start + moved))
            }
            .onEnded { value in
                let start = dragStart ?? position
                dragStart = nil
                guard abs(value.translation.width) >= Self.minimumTravel, let target = scrubbing else {
                    RemoteMediaTrace.trace.log("phone drag ended without moving")
                    scrubbing = nil
                    return
                }
                seek(to: target, from: start)
            }
    }

    private func seek(to target: Double, from start: Double) {
        RemoteMediaTrace.trace.log("phone seek to \(Int(target)) s from \(Int(start)) s")
        scrubbing = target
        seekSentAt = .now
        onSeek(target)
    }

    /// A drag the system took away (a scroll, a swipe back) ends without
    /// `onEnded`. It seeks nothing, and the bar follows the HomePad again.
    private func dropCancelledDrag() {
        guard let start = dragStart else { return }
        RemoteMediaTrace.trace.log("phone drag cancelled, began at \(Int(start)) s")
        dragStart = nil
        scrubbing = nil
    }

    /// Lets the bar follow the HomePad again once it reports the position the drag asked for, or a few
    /// seconds after the seek if it never does. Never while the finger is still on the bar.
    private func releaseScrubbing(duration: Double) {
        let reported = track.position(after: 0) ?? 0
        guard dragStart == nil, let target = scrubbing else { return }
        let waited = seekSentAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
        let lands = abs(reported - target) <= Self.landing
        RemoteMediaTrace.trace.log("phone status at \(Int(reported)) s, holding \(Int(target)) s, "
                                   + (lands ? "landed" : waited > Self.patience ? "gave up" : "still holding"))
        if lands || waited > Self.patience {
            scrubbing = nil
            seekSentAt = nil
        }
    }

    /// How close a reported position has to be to the seek, in seconds, to follow it again.
    static let landing: Double = 2
    /// How long the bar holds the seek when no status reports it, in seconds.
    static let patience: Double = 4
    /// How far a finger has to travel, in points, for its release to seek. A tap seeks nothing.
    static let minimumTravel: CGFloat = 2
    /// How far one VoiceOver swipe moves, in seconds.
    static let accessibilityStep: Double = 15
    static let barHeight: CGFloat = 6
    static let touchedBarHeight: CGFloat = 12

    /// "3:07", or "1:02:45" past an hour.
    static func time(_ seconds: Double) -> String {
        let duration = Duration.seconds(max(0, seconds.rounded(.down)))
        return seconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }
}
