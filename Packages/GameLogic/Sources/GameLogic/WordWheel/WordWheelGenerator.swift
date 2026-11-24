import Foundation

extension WordWheel {
    /// The words Word Wheel knows. See `Resources/WORDLISTS.md` for sources.
    ///
    /// - `answers`: familiar words a wheel expects (12dicts `3of6game` ∩ ENABLE, core vocabulary only).
    /// - `extras`: every other accepted word (the rest of ENABLE): scores as a bonus word.
    ///
    /// Both lists only hold lowercase a–z words of 4+ letters with at most 7 distinct letters and
    /// no "s": wheels never use "s", so plurals can't flood them.
    public struct Dictionary: Sendable {
        public let answers: [String]
        let answerMasks: [UInt32]
        let answerSet: Set<String>
        let extras: Set<String>
        /// Distinct 7-letter masks of answer pangrams, ascending (the wheels that can be built).
        let pangramMasks: [UInt32]

        public init(answers: [String], extras: [String]) {
            let blocked = WordLists.blocklist
            let clean = Array(Set(answers.map { $0.lowercased() }.filter { Self.isEligible($0) && !blocked.contains($0) })).sorted()
            self.answers = clean
            answerMasks = clean.map(WordWheel.mask)
            answerSet = Set(clean)
            self.extras = Set(extras.map { $0.lowercased() }.filter(Self.isEligible)).subtracting(answerSet)
            pangramMasks = Array(Set(answerMasks.filter { $0.nonzeroBitCount == 7 })).sorted()
        }

        /// The bundled lists, loaded once on first use (thread-safe; call off the main actor).
        public static var bundled: Dictionary { Cache.bundled }

        public func isAnswer(_ word: String) -> Bool { answerSet.contains(word) }
        public func isValid(_ word: String) -> Bool { answerSet.contains(word) || extras.contains(word) }

        /// Every answer that fits a wheel with these letters and center.
        public func answers(letters: UInt32, center: Character) -> [String] {
            let c = WordWheel.mask(String(center))
            return zip(answers, answerMasks).compactMap { word, m in
                m & ~letters == 0 && m & c != 0 ? word : nil
            }
        }

        static func isEligible(_ word: String) -> Bool {
            word.count >= WordWheel.minLength
                && word.utf8.allSatisfy { $0 >= 97 && $0 <= 122 && $0 != 115 }   // a–z, no "s"
                && WordWheel.mask(word).nonzeroBitCount <= 7
        }

        private enum Cache {
            static let bundled = Dictionary(answers: load("wheelAnswers"), extras: load("wheelGuesses"))

            static func load(_ name: String) -> [String] {
                guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    assertionFailure("Missing word list \(name).txt")
                    return []
                }
                return text.split(whereSeparator: \.isNewline).map(String.init)
            }
        }
    }

    /// Bit set of the letters a–z in `word`.
    static func mask(_ word: String) -> UInt32 {
        var m: UInt32 = 0
        for b in word.utf8 where b >= 97 && b <= 122 { m |= 1 << UInt32(b - 97) }
        return m
    }

    static func letters(of mask: UInt32) -> [Character] {
        (0..<26).filter { mask & (1 << UInt32($0)) != 0 }.map { Character(UnicodeScalar(UInt8(97 + $0))) }
    }

    // MARK: Generator

    /// What makes a good wheel: enough familiar answers to feel rich, not so many it's a slog.
    public static let answerRange = 20...60
    public static let maxPointsRange = 50...300

    /// Builds a wheel around a pangram: picks a 7-letter set and a center whose answer count and
    /// total points are in range. Deterministic for a given generator state and dictionary.
    public static func generate<R: RandomNumberGenerator>(using rng: inout R,
                                                          dictionary: Dictionary = .bundled) -> Puzzle {
        let sets = dictionary.pangramMasks
        guard !sets.isEmpty else { return fallback }
        var best: (puzzle: Puzzle, distance: Int)?
        for _ in 0..<400 {
            let set = sets[Int.random(in: 0..<sets.count, using: &rng)]
            for center in letters(of: set).shuffled(using: &rng) {
                let answers = dictionary.answers(letters: set, center: center)
                let puzzle = Puzzle(center: center, outer: letters(of: set).filter { $0 != center }, answers: answers)
                let distance = Self.distance(answers.count, answerRange) + Self.distance(puzzle.maxPoints, maxPointsRange)
                if distance == 0 { return puzzle }
                if best.map({ distance < $0.distance }) ?? true { best = (puzzle, distance) }
            }
        }
        return best?.puzzle ?? fallback
    }

    /// The wheel with exactly these letters (for fixed scenarios such as UI tests).
    public static func puzzle(center: Character, outer: [Character], dictionary: Dictionary = .bundled) -> Puzzle {
        let letters = mask(String(outer) + String(center))
        return Puzzle(center: center, outer: outer, answers: dictionary.answers(letters: letters, center: center))
    }

    private static func distance(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        value < range.lowerBound ? range.lowerBound - value : value > range.upperBound ? value - range.upperBound : 0
    }

    /// Used only if the word lists are missing.
    static let fallback = Puzzle(center: "a", outer: Array("einprt"),
                                 answers: ["painter", "pertain", "repaint", "paint", "pant", "part", "pain", "pair",
                                           "pane", "pear", "rant", "rate", "tear", "near", "neat", "trap", "train",
                                           "taper", "tiara", "parent", "patient", "pirate", "retain", "retrain",
                                           "terrain", "attain", "entrap", "pantry"].filter { $0.allSatisfy("aeinprt".contains) })
}
