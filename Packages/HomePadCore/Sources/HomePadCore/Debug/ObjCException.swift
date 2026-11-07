import Foundation
import HomePadObjC

/// Runs `body` and returns the reason of the Objective-C exception it raised, or
/// nil. For framework calls that raise instead of returning an error, which
/// Swift cannot catch (AVAudioNode taps, MediaPlayer's private classes).
public func catchingObjCException(_ body: () -> Void) -> String? {
    HPCatchException(body).map { $0.reason ?? $0.name.rawValue }
}
