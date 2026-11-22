import Foundation

/// Hangman: reveal a hidden word or phrase one letter at a time before running out of lives.
public enum Hangman {
    public static let maxLives = 6
    public static let maxPhraseLength = 32
    public static let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    /// Characters shown from the start and never guessed.
    public static func isAutoRevealed(_ c: Character) -> Bool { c == " " || c == "-" || c == "'" }

    /// Normalizes user input: folds accents, lowercases, unifies apostrophes/dashes and collapses spaces.
    public static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public enum PhraseProblem: Equatable, Sendable {
        case tooShort, tooLong, invalidCharacters

        public var message: String {
            switch self {
            case .tooShort: "Use at least 2 letters"
            case .tooLong: "Keep it under \(Hangman.maxPhraseLength) characters"
            case .invalidCharacters: "Letters, spaces, hyphens and apostrophes only"
            }
        }
    }

    /// Checks a normalized phrase typed by a player.
    public static func problem(with phrase: String) -> PhraseProblem? {
        let p = normalize(phrase)
        if !p.allSatisfy({ alphabet.contains($0) || isAutoRevealed($0) }) { return .invalidCharacters }
        if p.filter({ alphabet.contains($0) }).count < 2 { return .tooShort }
        if p.count > maxPhraseLength { return .tooLong }
        return nil
    }

    public enum Status: String, Codable, Sendable {
        case playing, won, lost
    }

    public enum GuessResult: Equatable, Sendable {
        /// The letter appears `count` times.
        case hit(count: Int)
        case miss
        /// Already guessed, not a letter, or the game is over.
        case ignored
    }

    public struct State: Codable, Equatable, Sendable {
        /// Normalized phrase (lowercase letters, spaces, hyphens, apostrophes).
        public let phrase: String
        public let category: String?
        public let hint: String?
        /// Letters guessed so far, in order.
        public private(set) var guessed: String = ""
        public private(set) var status: Status = .playing

        public init(phrase: String, category: String? = nil, hint: String? = nil) {
            let normalized = Hangman.normalize(phrase)
            self.phrase = normalized
            self.category = category
            let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hint = trimmed?.isEmpty == false ? trimmed : nil
        }

        public var letters: Set<Character> { Set(phrase.filter { Hangman.alphabet.contains($0) }) }
        public var wrongGuesses: [Character] { Array(guessed.filter { !phrase.contains($0) }) }
        public var correctGuesses: [Character] { Array(guessed.filter { phrase.contains($0) }) }
        public var misses: Int { wrongGuesses.count }
        public var livesLeft: Int { max(0, Hangman.maxLives - misses) }
        public var isOver: Bool { status != .playing }

        public func isRevealed(_ c: Character) -> Bool {
            Hangman.isAutoRevealed(c) || guessed.contains(c) || status == .lost
        }

        /// The phrase with unrevealed letters replaced by `placeholder`.
        public func masked(placeholder: Character = "_") -> String {
            String(phrase.map { isRevealed($0) ? $0 : placeholder })
        }

        @discardableResult
        public mutating func guess(_ raw: Character) -> GuessResult {
            let letter = Character(raw.lowercased())
            guard status == .playing, Hangman.alphabet.contains(letter), !guessed.contains(letter) else { return .ignored }
            guessed.append(letter)
            let count = phrase.filter { $0 == letter }.count
            if count > 0 {
                if letters.isSubset(of: Set(guessed)) { status = .won }
                return .hit(count: count)
            }
            if misses >= Hangman.maxLives { status = .lost }
            return .miss
        }
    }

    // MARK: Computer word choice

    /// Relative difficulty of guessing an entry: short entries with few distinct, rare letters are hardest.
    public static func difficultyScore(_ entry: String) -> Double {
        // Integer arithmetic (tenths) keeps the score independent of Set iteration order,
        // so sorting by it is a strict, deterministic ordering.
        let letters = entry.filter { alphabet.contains($0) }
        let unique = Set(letters)
        let common = Set("etaoinshrdlu")
        let rare = Set("jqxzkvwyb")
        let rareCount = unique.filter { rare.contains($0) }.count
        let uncommonCount = unique.filter { !rare.contains($0) && !common.contains($0) }.count
        let repeats = letters.count - unique.count
        var tenths: Int = 120
        tenths -= 10 * unique.count
        tenths += 16 * rareCount
        tenths += 6 * uncommonCount
        tenths -= 4 * repeats
        return Double(tenths) / 10
    }

    /// Entries for a difficulty: the easiest, middle or hardest third of the pool (by `difficultyScore`).
    public static func pool(for difficulty: Difficulty, in entries: [String]) -> [String] {
        let scored: [(entry: String, score: Double)] = entries.map { ($0, difficultyScore($0)) }
        let ordered = scored.sorted { (a: (entry: String, score: Double), b: (entry: String, score: Double)) -> Bool in
            if a.score != b.score { return a.score < b.score }
            return a.entry < b.entry
        }
        let sorted: [String] = ordered.map { $0.entry }
        guard sorted.count >= 3 else { return sorted }
        let third = sorted.count / 3
        switch difficulty {
        case .easy: return Array(sorted[..<third])
        case .medium: return Array(sorted[third..<(sorted.count - third)])
        case .hard, .expert: return Array(sorted[(sorted.count - third)...])
        }
    }

    /// Picks a clean entry from `category` (or any category when `nil`) for the given difficulty.
    public static func randomPuzzle<R: RandomNumberGenerator>(
        category: WordCategory?, difficulty: Difficulty, using rng: inout R
    ) -> State {
        let chosen = category ?? WordCategory.all.randomElement(using: &rng)!
        let entries = chosen.entries.filter { WordLists.isClean($0) && problem(with: $0) == nil }
        let candidates = pool(for: difficulty, in: entries)
        let phrase = candidates.randomElement(using: &rng) ?? "airplane"
        return State(phrase: phrase, category: chosen.title)
    }
}
