/// Word Guess hints: suggest a next guess that fits every clue and narrows the answers the most.
extension WordGuess {
    /// A suggested next guess and why it's a good one.
    public struct Suggestion: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// No guesses yet: a strong first word.
            case opener
            /// Several words still fit: the one that splits them best.
            case narrow
            /// Exactly one word fits the clues.
            case onlyOne
        }

        public let word: String
        public let kind: Kind
        /// How many words still fit the clues before this guess.
        public let remaining: Int
        /// Average number of words that would still fit after guessing `word`.
        public let expectedLeft: Double
        /// Letters `word` tries for the first time, most useful first (at most three).
        public let newLetters: [Character]

        public var title: String {
            switch kind {
            case .opener: "Try \(word.uppercased())"
            case .narrow: "Try \(word.uppercased())"
            case .onlyOne: "Only one word fits!"
            }
        }

        public var explanation: String {
            let upper = word.uppercased()
            let letters = Self.list(newLetters.map { String($0).uppercased() })
            switch kind {
            case .onlyOne:
                return "Every clue points to \(upper)."
            case .opener:
                return "A strong first guess: \(upper) tries \(letters), some of the most common letters in the answers."
            case .narrow:
                let left = expectedLeft < 1.5 ? "should all but pin it down" : "should leave about \(Int(expectedLeft.rounded()))"
                if newLetters.isEmpty {
                    return "\(remaining) words still fit your clues. \(upper) fits them too and splits them best — it \(left)."
                }
                return "\(remaining) words still fit your clues. \(upper) tests \(letters), the most useful letters left, and \(left)."
            }
        }

        static func list(_ items: [String]) -> String {
            switch items.count {
            case 0: ""
            case 1: items[0]
            case 2: "\(items[0]) and \(items[1])"
            default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
            }
        }
    }

    /// `true` if `word` could be the answer given every guess so far.
    public static func fits(_ word: String, guesses: [Guess]) -> Bool {
        guesses.allSatisfy { score(guess: $0.word, answer: word) == $0.states }
    }

    /// Words from `answers` that fit every clue; if none do (a friend's word that isn't a common
    /// answer), the words from `allWords` that fit.
    public static func remainingWords(after guesses: [Guess], answers: [String], allWords: [String]) -> [String] {
        let fitting = answers.filter { fits($0, guesses: guesses) }
        if !fitting.isEmpty || allWords.isEmpty { return fitting }
        return allWords.filter { fits($0, guesses: guesses) }
    }

    /// The best next guess: always a word that fits every clue (so it also obeys Hard Mode), chosen
    /// to leave the fewest possible answers on average. Uses only what the guesses revealed.
    public static func suggestion(after guesses: [Guess], hardMode: Bool,
                                  answers: [String] = WordLists.answers,
                                  allWords: [String] = []) -> Suggestion? {
        var candidates = remainingWords(after: guesses, answers: answers, allWords: allWords).sorted()
        if hardMode { candidates = candidates.filter { hardModeViolation(for: $0, previous: guesses) == nil } }
        guard !candidates.isEmpty else { return nil }
        let tested = Set(guesses.flatMap { Array($0.word) })
        if candidates.count == 1 {
            return Suggestion(word: candidates[0], kind: .onlyOne, remaining: 1, expectedLeft: 1, newLetters: [])
        }

        let words = candidates.map { Array($0.utf8).map { $0 &- 97 } }
        let n = words.count
        // How many candidates contain each letter, and each letter in each spot.
        var contains = [Int](repeating: 0, count: 26)
        var positional = [[Int]](repeating: [Int](repeating: 0, count: 26), count: wordLength)
        for w in words {
            var seen: UInt32 = 0
            for (i, l) in w.enumerated() {
                positional[i][Int(l)] += 1
                if seen & (1 << UInt32(l)) == 0 { contains[Int(l)] += 1; seen |= 1 << UInt32(l) }
            }
        }
        // Quick score: letters that split the candidates near half are worth the most.
        func quick(_ w: [UInt8]) -> Int {
            var total = 0, seen: UInt32 = 0
            for (i, l) in w.enumerated() {
                let p = positional[i][Int(l)]
                total += min(p, n - p)
                if seen & (1 << UInt32(l)) == 0 {
                    seen |= 1 << UInt32(l)
                    total += 2 * min(contains[Int(l)], n - contains[Int(l)])
                }
            }
            return total
        }
        let ranked = words.indices.map { (index: $0, quick: quick(words[$0])) }
            .sorted { $0.quick != $1.quick ? $0.quick > $1.quick : $0.index < $1.index }
        // Exact check on the most promising: the average size of the group of answers that would
        // give the same colors (smaller is better).
        var best: (index: Int, expected: Double)?
        var buckets = [Int](repeating: 0, count: 243)
        for entry in ranked.prefix(40) {
            for i in buckets.indices { buckets[i] = 0 }
            let g = words[entry.index]
            for a in words { buckets[pattern(g, a)] += 1 }
            let expected = Double(buckets.reduce(0) { $0 + $1 * $1 }) / Double(n)
            if best.map({ expected < $0.expected - 1e-9 }) ?? true { best = (entry.index, expected) }
        }
        let chosen = best!
        let word = candidates[chosen.index]
        let fresh = Array(Set(word).subtracting(tested))
            .sorted { a, b in
                let ca = contains[Int(a.asciiValue! - 97)], cb = contains[Int(b.asciiValue! - 97)]
                return ca != cb ? ca > cb : a < b
            }
        return Suggestion(word: word, kind: guesses.isEmpty ? .opener : .narrow, remaining: n,
                          expectedLeft: chosen.expected, newLetters: Array(fresh.prefix(3)))
    }

    /// The colors `guess` would get against `answer` as one number (base 3), letters 0...25.
    /// Matches `score(guess:answer:)`: exact matches first, then present letters left to right.
    static func pattern(_ guess: [UInt8], _ answer: [UInt8]) -> Int {
        var used: UInt8 = 0
        for i in 0..<wordLength where guess[i] == answer[i] { used |= 1 << UInt8(i) }
        let correct = used
        var code = 0, place = 1
        for i in 0..<wordLength {
            var state = 0
            if correct & (1 << UInt8(i)) != 0 {
                state = 2
            } else {
                for j in 0..<wordLength where used & (1 << UInt8(j)) == 0 && answer[j] == guess[i] {
                    state = 1
                    used |= 1 << UInt8(j)
                    break
                }
            }
            code += state * place
            place *= 3
        }
        return code
    }
}
