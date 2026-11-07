import Foundation

/// What HomePad does with the volume of the speakers Apple's player plays to,
/// one reading at a time (`MusicAirPlayVolume` reads twice a second).
///
/// - A reading wins. The speakers keep their own volume, so HomePad shows what
///   they read and leaves them alone.
/// - When they cannot be read (right after launch, before AirPlay answers),
///   HomePad shows the last level the person chose for them, or for the
///   speakers used last, and writes nothing.
/// - The one write HomePad makes on its own: when Apple's player first plays
///   to speakers after a launch, or after the speakers changed or went away,
///   and in the first `window` seconds they read louder than the person left
///   them, the person's exact last level goes back. It never raises a volume,
///   it stops as soon as the person sets a volume, and it tries at most
///   `maxRestores` times.
/// - While music plays after that, a reading that moved is a volume chosen
///   elsewhere (the AirPlay menu, the top of a HomePod, the Home app). It
///   becomes the level remembered for those speakers.
struct MusicVolumeRestore {
    struct Reading: Equatable {
        /// `MusicVolumeMemory.speakers(names:)`, nil when AirPlay names none.
        var speakers: String?
        var level: Double
        var canSet: Bool
        /// Apple's player plays.
        var isPlaying: Bool
    }

    enum Action: Equatable {
        case none
        /// Put this level, the person's last for these speakers, back on them.
        case restore(Double)
    }

    var memory: MusicVolumeMemory
    /// How long after playback starts a louder reading counts as the jump of a
    /// new AirPlay session rather than a choice made elsewhere.
    var window: TimeInterval = 8
    /// Readings this close to the remembered level are the same level. AirPlay
    /// rounds volume to its own steps.
    var tolerance = 0.03
    var maxRestores = 2

    /// The speakers of the readings since they last changed.
    private var speakers: String?
    /// True once Apple's player played to `speakers`.
    private var hasPlayed = false
    private var windowStart: Date?
    private var restores = 0
    private var personChoseInWindow = false

    init(memory: MusicVolumeMemory) {
        self.memory = memory
    }

    /// The level shown when the speakers cannot be read: the person's last for
    /// the speakers named now, else for the speakers used last.
    var fallbackLevel: Double? {
        speakers.flatMap(memory.level(for:)) ?? memory.lastLevel
    }

    /// The level to show for a reading. Nil when HomePad knows none.
    func shownLevel(_ reading: Reading) -> Double? {
        reading.canSet ? reading.level : fallbackLevel
    }

    /// The person set a volume: the slider, the assistant or the iPhone remote.
    mutating func personChose(_ level: Double) {
        if let key = speakers ?? memory.lastSpeakers {
            memory.remember(level, for: key)
        }
        if windowStart != nil { personChoseInWindow = true }
    }

    /// Takes a reading and says whether to put a level back.
    mutating func handle(_ reading: Reading, at now: Date) -> Action {
        if reading.speakers != speakers {
            speakers = reading.speakers
            hasPlayed = false
            windowStart = nil
        }
        guard let key = speakers, reading.canSet, reading.isPlaying else { return .none }
        if !hasPlayed {
            hasPlayed = true
            windowStart = now
            restores = 0
            personChoseInWindow = false
        }
        let saved = memory.level(for: key)
        if let start = windowStart {
            if now.timeIntervalSince(start) < window {
                guard !personChoseInWindow, restores < maxRestores,
                      let saved, reading.level > saved + tolerance else { return .none }
                restores += 1
                return .restore(saved)
            }
            windowStart = nil
        }
        let moved = saved.map { abs(reading.level - $0) > tolerance } ?? true
        if moved { memory.remember(reading.level, for: key) }
        return .none
    }
}
