import Foundation

/// Real-time safe noise synthesis: no allocation, no locks, deterministic for a seed.
///
/// - White: uniform random samples from a xorshift32 generator (flat spectrum).
/// - Pink: Paul Kellet's refined filter bank over white noise (-3 dB per octave).
/// - Brown: a leaky integrator over white noise (-6 dB per octave).
/// - Rain: a band-limited pink bed plus sparse, fast-decaying "drops" of
///   high-passed white noise.
///
/// Every color is scaled to a similar loudness (about 0.2 RMS) so switching
/// sounds never jumps in volume. Constants assume 44.1 to 48 kHz.
struct NoiseGenerator {
    private var rng: UInt32
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brownState: Float = 0
    private var rainLowpass: Float = 0
    private var dropEnvelope: Float = 0
    private var lastDropNoise: Float = 0

    /// Gains that bring each color to about 0.2 RMS.
    enum Level {
        static let white: Float = 0.35
        static let pink: Float = 0.11
        static let brown: Float = 3.5
    }

    /// Chance per sample that a rain drop starts (about 30 drops a second at 48 kHz).
    static let dropProbability: Float = 0.000_65
    /// Per-sample decay of a drop, about 15 ms to fade out.
    static let dropDecay: Float = 0.993

    init(seed: UInt32 = 0x9E37_79B9) {
        rng = seed == 0 ? 0x9E37_79B9 : seed
    }

    /// The next sample of the given sound, roughly within -1...1.
    mutating func next(_ sound: AmbientSound) -> Float {
        let sample: Float
        switch sound {
        case .white: sample = white() * Level.white
        case .pink: sample = pink()
        case .brown: sample = brown()
        case .rain: sample = rain()
        }
        return min(1, max(-1, sample))
    }

    /// Uniform white noise in -1...1.
    mutating func white() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    private mutating func pink() -> Float {
        let w = white()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let sum = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return sum * Level.pink
    }

    private mutating func brown() -> Float {
        brownState = (brownState + 0.02 * white()) / 1.02
        return brownState * Level.brown
    }

    private mutating func rain() -> Float {
        // A soft bed: pink noise with its deepest rumble removed.
        let bed = pink()
        rainLowpass += 0.01 * (bed - rainLowpass)
        let softened = (bed - rainLowpass) * 0.8

        // Sparse drops: short bursts of high-passed white noise.
        let dice = (white() + 1) / 2
        if dice < Self.dropProbability {
            dropEnvelope = 0.25 + 0.75 * (white() + 1) / 2
        }
        dropEnvelope *= Self.dropDecay
        let noise = white()
        let crisp = noise - lastDropNoise
        lastDropNoise = noise
        return softened + crisp * dropEnvelope * 0.35
    }
}

/// A one-pole smoother that glides toward a target gain, so starts, stops and
/// volume changes never click.
struct GainRamp {
    private(set) var current: Float
    var target: Float
    /// Fraction of the remaining distance covered per sample.
    let coefficient: Float

    init(initial: Float = 0, target: Float = 0, coefficient: Float = 0.0005) {
        current = initial
        self.target = target
        self.coefficient = coefficient
    }

    mutating func next() -> Float {
        current += (target - current) * coefficient
        return current
    }
}
