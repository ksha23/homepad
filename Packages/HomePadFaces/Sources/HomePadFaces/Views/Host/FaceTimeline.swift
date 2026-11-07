import HomePadCore
import SwiftUI

/// How often a face redraws. Faces ask for the slowest cadence that still
/// looks right. Thumbnails drop to once a minute, a face behind the Home
/// Screen shows no clock and animates at a few frames a second, and motion
/// stops while the display is dimmed, red for the night or asleep.
enum FaceCadence: Equatable {
    case minute
    case second
    /// Continuous animation capped at a frame rate.
    case frames(Double)
    /// One picture, redrawn only when the face's inputs change.
    case still

    /// The cadence actually used:
    /// - Thumbnails, and faces beside the one on the wall (`\.faceIsBeside`),
    ///   never redraw faster than once a minute.
    /// - Asleep, the screen is covered, so clocks tick once a minute and motion stops.
    /// - Dimmed or at night, motion stops. Clocks keep their seconds, because someone
    ///   close enough to see them is looking.
    /// - Behind the Home Screen a face shows only its picture or background
    ///   (`faceForeground()`), so nothing there needs seconds, and motion is
    ///   capped at `frostedFrameRate`.
    func effective(isThumbnail: Bool, isFrosted: Bool = false, isBeside: Bool = false,
                   condition: DisplayCondition = .ambient) -> FaceCadence {
        if isThumbnail || isBeside { return .minute }
        switch self {
        case .frames(let fps):
            if !condition.allowsMotion { return .still }
            return isFrosted ? .frames(min(fps, Self.frostedFrameRate)) : self
        case .second:
            return condition == .sleeping || isFrosted ? .minute : self
        case .minute, .still:
            return self
        }
    }

    /// Frames a second for continuous motion behind the frost.
    static let frostedFrameRate: Double = 2
}

/// A `TimelineView` that applies the face cadence rules and the debug time
/// offset, and hands the face the date to draw.
struct FaceTimeline<Content: View>: View {
    private let cadence: FaceCadence
    private let content: (Date) -> Content
    @Environment(\.faceTimeOffset) private var offset
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.isFrosted) private var isFrosted
    @Environment(\.faceIsBeside) private var isBeside
    @Environment(\.displayCondition) private var condition

    init(_ cadence: FaceCadence, @ViewBuilder content: @escaping (Date) -> Content) {
        self.cadence = cadence
        self.content = content
    }

    var body: some View {
        // One timeline whatever the cadence. A different TimelineView per cadence
        // made a cadence change (a face going from minutes to seconds as someone
        // walks up) rebuild the whole face, so its layout jumped instead of moving.
        let effective = cadence.effective(isThumbnail: isThumbnail, isFrosted: isFrosted, isBeside: isBeside,
                                          condition: condition)
        TimelineView(FaceSchedule(cadence: effective)) { context in
            content(context.date.addingTimeInterval(offset))
        }
    }
}

/// Ticks on the minute, on the second, a few times a second, or not at all,
/// as one schedule type, so changing the cadence keeps the timeline's identity.
///
/// The first entry is the moment the schedule starts, the rest fall on whole
/// minutes or seconds. A clock that slows from seconds to minutes as someone
/// walks away keeps its hands where they are instead of turning them back to
/// the start of the minute, which the face's proximity animation showed as a
/// backward sweep.
struct FaceSchedule: TimelineSchedule {
    let cadence: FaceCadence

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let interval: TimeInterval
        switch cadence {
        case .minute: interval = 60
        case .second: interval = 1
        case .frames(let fps): interval = 1 / max(fps, 1)
        case .still:
            // Drawn once at the moment it stopped, so motion freezes where it was
            // instead of jumping to a whole-minute position. A daily entry is as
            // close to never as a periodic schedule gets.
            interval = 86_400
            return sequence(first: startDate) { $0.addingTimeInterval(interval) }
        }
        // After the first, whole minutes and seconds line up with the clock, so
        // a minute face changes exactly when the minute does.
        return sequence(first: startDate) { Self.boundary(after: $0, every: interval) }
    }

    /// The first multiple of `interval` (since the reference date) after `date`.
    static func boundary(after date: Date, every interval: TimeInterval) -> Date {
        let count = (date.timeIntervalSinceReferenceDate / interval).rounded(.down) + 1
        return Date(timeIntervalSinceReferenceDate: count * interval)
    }
}
