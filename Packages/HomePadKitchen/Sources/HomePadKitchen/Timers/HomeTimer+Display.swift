import Foundation
import HomePadCore

extension HomeTimer {
    /// 1 when just started, 0 when done, for rings.
    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return remaining(at: now) / duration
    }

    /// "Paused" or "Done" for timers that are not counting down, else nil.
    var statusText: String? {
        switch status {
        case .running: nil
        case .paused: "Paused"
        case .finished: "Done"
        }
    }
}
