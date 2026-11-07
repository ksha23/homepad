import CoreGraphics
import Foundation

/// Slowly moves always-on content a few points around a small orbit so static
/// pixels (clock digits, widget edges) do not burn into the OLED panels of the
/// 2024 and later iPad Pros. Each step lasts `period` seconds, and the view
/// animates between steps with `Theme.Motion.ambient`, so the drift is invisible.
enum BurnInShift {
    /// Steps in one orbit: two rings (full and half amplitude) of eight points each.
    static let steps = 16

    /// The offset to apply at `date`.
    /// - Parameters:
    ///   - amplitude: Largest shift in points. Zero disables shifting.
    ///   - period: Seconds between steps.
    static func offset(at date: Date, amplitude: Double, period: TimeInterval = 90) -> CGSize {
        guard amplitude > 0, period > 0 else { return .zero }
        let index = Int((date.timeIntervalSinceReferenceDate / period).rounded(.down)) % steps
        let angle = Double(index % 8) * .pi / 4
        let radius = index < 8 ? amplitude : amplitude / 2
        return CGSize(width: (cos(angle) * radius).rounded(), height: (sin(angle) * radius).rounded())
    }
}
