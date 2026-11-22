extension TileMatch {
    /// The families of tile faces. Numbered suits run 1–9; honours have a few distinct faces;
    /// bonus sets contain four different faces that all match each other.
    public enum Suit: String, CaseIterable, Codable, Sendable {
        case ocean, forest, ember
        case weather, charm
        case treasure, critter

        /// How many distinct faces the suit has.
        public var faceCount: Int {
            switch self {
            case .ocean, .forest, .ember: 9
            case .weather: 4
            case .charm: 3
            case .treasure, .critter: 4
            }
        }

        public var isNumbered: Bool { self == .ocean || self == .forest || self == .ember }
        /// Any two faces of a bonus suit match each other.
        public var isBonus: Bool { self == .treasure || self == .critter }
    }

    public struct Face: Hashable, Codable, Sendable, CustomStringConvertible {
        public let suit: Suit
        /// 1-based rank (1...suit.faceCount).
        public let rank: Int

        public init(_ suit: Suit, _ rank: Int) {
            precondition((1...suit.faceCount).contains(rank), "rank out of range")
            self.suit = suit
            self.rank = rank
        }

        public func matches(_ other: Face) -> Bool {
            suit == other.suit && (suit.isBonus || rank == other.rank)
        }

        /// Faces that match each other share a key.
        public var matchKey: Face { suit.isBonus ? Face(suit, 1) : self }

        public var description: String { "\(suit.rawValue)\(rank)" }

        /// Every distinct face (42 in total).
        public static let all: [Face] = Suit.allCases.flatMap { suit in
            (1...suit.faceCount).map { Face(suit, $0) }
        }
    }

    /// Matching face pairs for a deal of `tileCount` tiles.
    ///
    /// The full 144-tile set holds four copies of every regular face and one of each bonus face.
    /// Smaller deals draw whole groups of four (two pairs) from a shuffled set of groups so
    /// there are still choices to make between identical faces.
    static func facePairs<R: RandomNumberGenerator>(count tileCount: Int, using rng: inout R) -> [(Face, Face)] {
        precondition(tileCount.isMultiple(of: 2) && tileCount <= 144, "unsupported tile count")
        // Each group yields two matching pairs.
        var groups: [[(Face, Face)]] = Face.all.filter { !$0.suit.isBonus }.map { [($0, $0), ($0, $0)] }
        for suit in Suit.allCases where suit.isBonus {
            groups.append([(Face(suit, 1), Face(suit, 2)), (Face(suit, 3), Face(suit, 4))])
        }
        groups.shuffle(using: &rng)
        var pairs: [(Face, Face)] = []
        var needed = tileCount / 2
        for group in groups where needed > 0 {
            let take = group.shuffled(using: &rng).prefix(min(2, needed))
            pairs.append(contentsOf: take)
            needed -= take.count
        }
        return pairs.shuffled(using: &rng)
    }
}
