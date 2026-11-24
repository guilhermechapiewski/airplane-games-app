/// A fast, deterministic pseudo-random generator (SplitMix64).
///
/// Used by every puzzle generator so that games can be reproduced from a seed
/// and tests are deterministic. Not suitable for cryptography.
public struct SeededRandom: RandomNumberGenerator, Sendable, Codable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    /// Creates a generator seeded from the system's random source.
    public init() {
        var system = SystemRandomNumberGenerator()
        self.state = system.next()
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SeededRandom {
    /// A seed derived from `text` with 64-bit FNV-1a: stable across runs, devices and Swift
    /// versions (unlike `Hasher`), so puzzles seeded from a name are the same for everyone.
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
