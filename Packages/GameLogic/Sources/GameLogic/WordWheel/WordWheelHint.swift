/// Word Wheel hints: a clue for one answer the player hasn't found, revealed a little more each time.
extension WordWheel {
    /// A clue for one unfound answer. Level 1: its length and first letter; level 2: the first two
    /// letters; level 3: the first two and the last letter.
    public struct Clue: Codable, Equatable, Sendable {
        public static let maxLevel = 3

        public let word: String
        public private(set) var level: Int

        public init(word: String, level: Int = 1) {
            self.word = word.lowercased()
            self.level = min(max(1, level), Self.maxLevel)
        }

        public var canRevealMore: Bool { level < Self.maxLevel }

        /// Reveals one more step. Returns `false` at the last level.
        @discardableResult
        public mutating func revealMore() -> Bool {
            guard canRevealMore else { return false }
            level += 1
            return true
        }

        /// Positions of the letters shown at this level.
        public var revealed: Set<Int> {
            let n = word.count
            switch level {
            case 1: return [0]
            case 2: return [0, 1]
            default: return [0, 1, n - 1]
            }
        }

        /// The word with hidden letters as `nil`.
        public var pattern: [Character?] {
            let shown = revealed
            return word.enumerated().map { shown.contains($0.offset) ? $0.element : nil }
        }

        /// "A 6-letter word starting with T" (level 1), "…starting with TR" (2),
        /// "…starting with TR and ending in N" (3).
        public var title: String {
            let letters = Array(word.uppercased())
            let n = letters.count
            let lead = "\(Self.article(for: n)) \(n)-letter word starting with "
            switch level {
            case 1: return lead + String(letters[0])
            case 2: return lead + String(letters[0...1])
            default: return lead + String(letters[0...1]) + " and ending in " + String(letters[n - 1])
            }
        }

        /// The pattern read aloud: "T, R, blank, blank, blank, N".
        public var spokenPattern: String {
            pattern.map { $0.map { String($0).uppercased() } ?? "blank" }.joined(separator: ", ")
        }

        /// "an" before numbers that start with a vowel sound (8, 11, 18).
        static func article(for n: Int) -> String {
            [8, 11, 18].contains(n) ? "An" : "A"
        }
    }

    /// How many unfound answers have a given length.
    public struct LengthCount: Equatable, Sendable {
        public let length: Int
        public let count: Int
    }
}

extension WordWheel.State {
    /// Unfound answers grouped by length, shortest first.
    public var answersLeftByLength: [WordWheel.LengthCount] {
        Dictionary(grouping: missedAnswers, by: \.count)
            .map { WordWheel.LengthCount(length: $0.key, count: $0.value.count) }
            .sorted { $0.length < $1.length }
    }

    /// The next clue: more of `current` while it's unfound and has more to show, otherwise a clue
    /// for a random unfound answer (never the word just hinted, unless it's the only one left).
    /// `nil` when every answer is found or the wheel is over.
    public func nextClue<R: RandomNumberGenerator>(after current: WordWheel.Clue?,
                                                   using rng: inout R) -> WordWheel.Clue? {
        guard !isFinished else { return nil }
        let left = missedAnswers
        if var clue = current, left.contains(clue.word), clue.canRevealMore {
            clue.revealMore()
            return clue
        }
        let others = left.filter { $0 != current?.word }
        guard let word = (others.isEmpty ? left : others).randomElement(using: &rng) else { return nil }
        return WordWheel.Clue(word: word)
    }
}
