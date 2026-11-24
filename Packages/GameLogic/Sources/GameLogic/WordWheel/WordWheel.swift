import Foundation

/// Word Wheel: seven letters, one in the center. Spell words of four or more letters that use
/// the center letter; letters can be reused. Every wheel has at least one pangram, a word that
/// uses all seven letters.
public enum WordWheel {
    public static let minLength = 4
    public static let pangramBonus = 7
    /// Longest word the input accepts (no answer is longer than this).
    public static let maxInputLength = 19

    // MARK: Scoring

    /// 4-letter words score 1; longer words score 1 per letter; pangrams add 7.
    public static func points(for word: String, isPangram: Bool) -> Int {
        let base = word.count <= minLength ? 1 : word.count
        return base + (isPangram ? pangramBonus : 0)
    }

    /// `true` if `word` uses every one of `letters` (at least once each).
    public static func isPangram(_ word: String, letters: Set<Character>) -> Bool {
        letters.allSatisfy(word.contains)
    }

    // MARK: Ranks

    /// Ranks climb with points as a share of the wheel's maximum (the answers' total).
    public enum Rank: Int, CaseIterable, Codable, Comparable, Sendable {
        case starter, good, great, amazing, genius

        public var title: String {
            switch self {
            case .starter: "Starter"
            case .good: "Good"
            case .great: "Great"
            case .amazing: "Amazing"
            case .genius: "Genius"
            }
        }

        /// Share of the maximum points needed.
        public var fraction: Double {
            switch self {
            case .starter: 0
            case .good: 0.10
            case .great: 0.25
            case .amazing: 0.50
            case .genius: 0.70
            }
        }

        /// Points needed for this rank on a wheel worth `maxPoints`.
        public func threshold(maxPoints: Int) -> Int {
            Int((fraction * Double(maxPoints)).rounded(.up))
        }

        public var next: Rank? { Rank(rawValue: rawValue + 1) }

        public static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }

        /// The highest rank `points` reaches.
        public static func rank(points: Int, maxPoints: Int) -> Rank {
            allCases.last { points >= $0.threshold(maxPoints: maxPoints) } ?? .starter
        }

        /// The rank that marks a daily wheel as solved (and a regular wheel as won).
        public static let solved: Rank = .great
    }

    // MARK: Puzzle

    public struct Puzzle: Codable, Equatable, Hashable, Sendable {
        /// The required letter (lowercase).
        public let center: String
        /// The six ring letters, alphabetical (lowercase).
        public let outer: [String]
        /// Familiar words that count toward "found x of y", sorted.
        public let answers: [String]

        public init(center: Character, outer: [Character], answers: [String]) {
            self.center = String(center)
            self.outer = outer.map(String.init).sorted()
            self.answers = answers.sorted()
        }

        public var centerLetter: Character { Character(center) }
        public var letters: Set<Character> { Set(outer.map { Character($0) } + [centerLetter]) }

        public func isPangram(_ word: String) -> Bool { WordWheel.isPangram(word, letters: letters) }
        public var pangrams: [String] { answers.filter(isPangram) }
        public var maxPoints: Int { answers.reduce(0) { $0 + WordWheel.points(for: $1, isPangram: isPangram($1)) } }

        public func threshold(_ rank: Rank) -> Int { rank.threshold(maxPoints: maxPoints) }
        public func rank(points: Int) -> Rank { Rank.rank(points: points, maxPoints: maxPoints) }

        /// Why `word` can't be entered (ignoring the word list and what was already found), or `nil`.
        public func shapeProblem(_ word: String) -> Rejection? {
            if word.count < WordWheel.minLength { return .tooShort }
            let letters = self.letters
            if !word.allSatisfy(letters.contains) { return .badLetters }
            if !word.contains(centerLetter) { return .missingCenter }
            return nil
        }
    }

    // MARK: Entry results

    public enum Rejection: String, Error, Codable, Sendable {
        case tooShort, missingCenter, badLetters, notInList, alreadyFound

        public var message: String {
            switch self {
            case .tooShort: "Too short"
            case .missingCenter: "Needs the center letter"
            case .badLetters: "Use only the wheel's letters"
            case .notInList: "Not in the word list"
            case .alreadyFound: "Already found"
            }
        }
    }

    public struct Accepted: Equatable, Sendable {
        public let word: String
        public let points: Int
        public let isPangram: Bool
        /// `false` for a bonus word: valid, scores, but isn't one of the wheel's answers.
        public let isAnswer: Bool
        public let rankBefore: Rank
        public let rankAfter: Rank

        public var rankedUp: Bool { rankAfter > rankBefore }
    }

    // MARK: State

    public struct State: Codable, Equatable, Sendable {
        public let puzzle: Puzzle
        /// The ring letters in their current (shuffled) display order, clockwise from the top.
        public private(set) var ring: [String]
        /// Accepted words in the order they were found.
        public private(set) var found: [String]
        public private(set) var input: String
        public private(set) var score: Int
        /// The wheel was ended with Finish / Reveal Answers.
        public private(set) var isFinished: Bool

        public init(puzzle: Puzzle) {
            self.puzzle = puzzle
            ring = puzzle.outer
            found = []
            input = ""
            score = 0
            isFinished = false
        }

        public var rank: Rank { puzzle.rank(points: score) }
        public var foundAnswers: [String] {
            let answers = Set(puzzle.answers)
            return found.filter(answers.contains)
        }
        public var bonusWords: [String] {
            let answers = Set(puzzle.answers)
            return found.filter { !answers.contains($0) }
        }
        public var missedAnswers: [String] {
            let found = Set(self.found)
            return puzzle.answers.filter { !found.contains($0) }
        }
        public var foundAllAnswers: Bool { missedAnswers.isEmpty }
        public var hasProgress: Bool { !found.isEmpty }

        /// Appends a wheel letter (any case); ignores other characters and over-long input.
        @discardableResult
        public mutating func type(_ letter: Character) -> Bool {
            let lower = Character(letter.lowercased())
            guard !isFinished, input.count < WordWheel.maxInputLength, puzzle.letters.contains(lower) else { return false }
            input.append(lower)
            return true
        }

        @discardableResult
        public mutating func deleteLetter() -> Bool {
            guard !input.isEmpty else { return false }
            input.removeLast()
            return true
        }

        public mutating func clearInput() { input = "" }

        /// Reorders the ring so that at least one letter moves.
        public mutating func shuffle<R: RandomNumberGenerator>(using rng: inout R) {
            let before = ring
            repeat { ring.shuffle(using: &rng) } while ring == before && ring.count > 1
        }

        /// Restores a saved ring order (must be a permutation of the ring letters).
        public mutating func setRing(_ order: [String]) {
            guard order.sorted() == puzzle.outer else { return }
            ring = order
        }

        /// Checks the typed word, scores it when valid, and clears the input either way.
        public mutating func submit(isValidWord: (String) -> Bool) -> Result<Accepted, Rejection> {
            let word = input
            input = ""
            return enter(word, isValidWord: isValidWord)
        }

        /// Checks and scores `word` (lowercase) without touching the input.
        public mutating func enter(_ word: String, isValidWord: (String) -> Bool) -> Result<Accepted, Rejection> {
            guard !isFinished else { return .failure(.notInList) }
            let word = word.lowercased()
            if let problem = puzzle.shapeProblem(word) { return .failure(problem) }
            if found.contains(word) { return .failure(.alreadyFound) }
            let isAnswer = puzzle.answers.contains(word)
            guard isAnswer || isValidWord(word) else { return .failure(.notInList) }
            let pangram = puzzle.isPangram(word)
            let points = WordWheel.points(for: word, isPangram: pangram)
            let before = rank
            found.append(word)
            score += points
            return .success(Accepted(word: word, points: points, isPangram: pangram, isAnswer: isAnswer,
                                     rankBefore: before, rankAfter: rank))
        }

        /// Ends the wheel (Finish / Reveal Answers).
        public mutating func finish() {
            isFinished = true
            input = ""
        }
    }
}
