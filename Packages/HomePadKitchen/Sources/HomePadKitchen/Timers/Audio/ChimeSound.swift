import Foundation

/// The timer sounds to choose from. A short curated list, like the Clock app's.
/// Sounds are synthesized, so they need no bundled audio and loop seamlessly.
public enum ChimeSound: String, Codable, CaseIterable, Sendable, Identifiable {
    case chime, bells, beeps, pulse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chime: "Chime"
        case .bells: "Bells"
        case .beeps: "Kitchen Beeps"
        case .pulse: "Soft Pulse"
        }
    }

    /// One note in a loop.
    struct Note {
        let frequency: Double
        let start: TimeInterval
        let length: TimeInterval
        let gain: Double
    }

    enum Voice {
        /// Struck bell: inharmonic partials with a long exponential decay.
        case bell
        /// Electronic beep: a bright tone with a short flat envelope.
        case beep
        /// Gentle sine swell, quiet enough for night.
        case swell
    }

    var voice: Voice {
        switch self {
        case .chime, .bells: .bell
        case .beeps: .beep
        case .pulse: .swell
        }
    }

    /// One loop: the notes and the loop length including the pause after them.
    var pattern: (notes: [Note], loopLength: TimeInterval) {
        switch self {
        case .chime:
            return ([Note(frequency: 1318.5, start: 0, length: 1.2, gain: 0.5),
                     Note(frequency: 987.8, start: 0.45, length: 1.6, gain: 0.5)], 2.4)
        case .bells:
            return ([Note(frequency: 784.0, start: 0, length: 1.0, gain: 0.45),
                     Note(frequency: 987.8, start: 0.25, length: 1.0, gain: 0.45),
                     Note(frequency: 1174.7, start: 0.5, length: 1.4, gain: 0.45)], 2.2)
        case .beeps:
            let beeps = (0..<4).map { Note(frequency: 2093, start: Double($0) * 0.16, length: 0.09, gain: 0.35) }
            return (beeps, 1.2)
        case .pulse:
            return ([Note(frequency: 523.3, start: 0, length: 0.9, gain: 0.45),
                     Note(frequency: 659.3, start: 0.9, length: 0.9, gain: 0.4)], 2.6)
        }
    }
}
