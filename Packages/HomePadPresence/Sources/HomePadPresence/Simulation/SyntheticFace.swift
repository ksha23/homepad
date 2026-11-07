import Foundation

/// Deterministic fake face embeddings for the simulator and tests.
/// Each member gets a stable random direction, and samples scatter around it.
enum SyntheticFace {
    static let dimension = 128

    /// The stable "identity" vector for a member.
    static func identity(for memberID: UUID) -> [Float] {
        var generator = SplitMix64(seed: memberID)
        return FaceMatcher.normalized((0..<dimension).map { _ in generator.nextFloat() * 2 - 1 })
    }

    /// One noisy sample of a member's face. `noise` around 0.1 to 0.3 mimics
    /// different angles and lighting.
    static func sample(around identity: [Float], noise: Float, seed: UInt64) -> [Float] {
        var generator = SplitMix64(state: seed)
        return FaceMatcher.normalized(identity.map { $0 + (generator.nextFloat() * 2 - 1) * noise })
    }
}

/// A tiny seedable random number generator (SplitMix64).
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(state: UInt64) {
        self.state = state
    }

    init(seed uuid: UUID) {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        state = bytes.prefix(8).reduce(0) { ($0 << 8) | UInt64($1) } ^ bytes.suffix(8).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
