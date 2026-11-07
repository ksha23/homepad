import Foundation
import Observation

/// Stops playback after a while, fading out over the last half minute.
/// Applies to whatever plays inside HomePad: sleep sounds, radio or Apple Music.
@MainActor
@Observable
final class SleepTimer {
    /// The curated choices offered in the UI and settings, in minutes. Zero means off.
    nonisolated static let choices = [0, 15, 30, 45, 60, 90]
    nonisolated static let fadeDuration: TimeInterval = 30

    private(set) var endDate: Date?

    /// Receives the fade level (1 down to 0) during the final `fadeDuration` seconds.
    @ObservationIgnored var onFade: ((Double) -> Void)?
    /// Called once when the timer runs out.
    @ObservationIgnored var onExpire: (() -> Void)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    var isActive: Bool { endDate != nil }

    func remaining(at now: Date = Date()) -> TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Starts or restarts the timer. Zero minutes cancels it.
    func start(minutes: Int) {
        guard minutes > 0 else { return cancel() }
        endDate = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        onFade?(1)
        tick()
    }

    func cancel() {
        tickTask?.cancel()
        tickTask = nil
        if endDate != nil { onFade?(1) }
        endDate = nil
    }

    /// 1 until the last `fadeDuration` seconds, then an equal-power curve down to 0.
    nonisolated static func fadeLevel(remaining: TimeInterval, fadeDuration: TimeInterval = fadeDuration) -> Double {
        if remaining <= 0 { return 0 }
        if fadeDuration <= 0 || remaining >= fadeDuration { return 1 }
        return sin(remaining / fadeDuration * .pi / 2)
    }

    /// "45 min" style label for a choice.
    nonisolated static func label(minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 60: "1 hour"
        case 90: "1.5 hours"
        default: "\(minutes) min"
        }
    }

    /// Sleeps until the fade starts, then checks twice a second to fade and stop.
    /// Before the fade there is nothing to do, so a 45 minute timer at night does
    /// not wake the iPad twice a second for 44 minutes.
    private func tick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let untilFade = (self?.remaining() ?? 0) - Self.fadeDuration
                try? await Task.sleep(for: .seconds(max(0.5, untilFade)))
                guard let self, let remaining = self.remaining() else { return }
                if remaining <= 0 {
                    self.endDate = nil
                    self.tickTask = nil
                    self.onExpire?()
                    self.onFade?(1)
                    return
                }
                if remaining < Self.fadeDuration {
                    self.onFade?(Self.fadeLevel(remaining: remaining))
                }
            }
        }
    }
}
