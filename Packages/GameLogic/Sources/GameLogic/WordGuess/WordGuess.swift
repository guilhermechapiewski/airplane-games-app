/// Word Guess: find a secret 5-letter word in 6 tries, with per-letter feedback.
public enum WordGuess {
    public static let wordLength = 5
    public static let maxGuesses = 6

    /// Feedback for one letter. Ordered so that a "better" state compares greater.
    public enum LetterState: Int, Codable, Sendable, Comparable, CaseIterable {
        case unknown, absent, present, correct

        public static func < (lhs: LetterState, rhs: LetterState) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Scores `guess` against `answer` (both 5 letters, any case) with correct duplicate handling:
    /// exact matches are assigned first, then remaining letters are marked present only while
    /// unmatched copies of that letter remain in the answer.
    public static func score(guess: String, answer: String) -> [LetterState] {
        let g = Array(guess.lowercased()), a = Array(answer.lowercased())
        precondition(g.count == a.count, "guess and answer must be the same length")
        var result = Array(repeating: LetterState.absent, count: g.count)
        var remaining: [Character: Int] = [:]
        for i in g.indices {
            if g[i] == a[i] {
                result[i] = .correct
            } else {
                remaining[a[i], default: 0] += 1
            }
        }
        for i in g.indices where result[i] != .correct {
            if let left = remaining[g[i]], left > 0 {
                result[i] = .present
                remaining[g[i]] = left - 1
            }
        }
        return result
    }

    public struct Guess: Codable, Equatable, Sendable {
        public let word: String
        public let states: [LetterState]
        public var isCorrect: Bool { states.allSatisfy { $0 == .correct } }
    }

    public enum Status: String, Codable, Sendable {
        case playing, won, lost
    }

    public enum SubmitError: Error, Equatable, Sendable {
        case gameOver
        case tooShort
        case notInWordList
        /// Hard mode: a revealed hint was not used. The message is ready to show.
        case mustUseHint(String)

        public var message: String {
            switch self {
            case .gameOver: "The game is over"
            case .tooShort: "Not enough letters"
            case .notInWordList: "Not in word list"
            case .mustUseHint(let message): message
            }
        }
    }

    /// Returns why `guess` breaks hard mode given the earlier guesses, or `nil` if it is allowed.
    /// Correct letters must stay in place, and every revealed letter must be reused at least as
    /// many times as it was revealed in a single guess.
    public static func hardModeViolation(for guess: String, previous: [Guess]) -> String? {
        let g = Array(guess.lowercased())
        for prior in previous {
            let letters = Array(prior.word)
            for i in letters.indices where prior.states[i] == .correct && g[i] != letters[i] {
                return "\(ordinal(i + 1)) letter must be \(String(letters[i]).uppercased())"
            }
        }
        for prior in previous {
            let letters = Array(prior.word)
            var required: [Character: Int] = [:]
            for i in letters.indices where prior.states[i] != .absent { required[letters[i], default: 0] += 1 }
            for (letter, count) in required.sorted(by: { $0.key < $1.key }) {
                if g.filter({ $0 == letter }).count < count {
                    return "Guess must contain \(String(letter).uppercased())"
                }
            }
        }
        return nil
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(n)th"
        }
    }

    public struct State: Codable, Equatable, Sendable {
        public let answer: String
        public let hardMode: Bool
        public private(set) var guesses: [Guess] = []
        /// Letters typed for the guess in progress (lowercase).
        public private(set) var current: String = ""
        public private(set) var status: Status = .playing

        public init(answer: String, hardMode: Bool = false) {
            precondition(answer.count == WordGuess.wordLength)
            self.answer = answer.lowercased()
            self.hardMode = hardMode
        }

        public var isOver: Bool { status != .playing }
        public var hasProgress: Bool { !guesses.isEmpty || !current.isEmpty }

        /// Appends a letter to the current guess. Returns `false` if it was ignored.
        @discardableResult
        public mutating func type(_ letter: Character) -> Bool {
            guard status == .playing, current.count < WordGuess.wordLength else { return false }
            let lower = Character(letter.lowercased())
            guard lower.isASCII, lower.isLetter else { return false }
            current.append(lower)
            return true
        }

        /// Removes the last typed letter. Returns `false` if there was nothing to delete.
        @discardableResult
        public mutating func deleteLetter() -> Bool {
            guard status == .playing, !current.isEmpty else { return false }
            current.removeLast()
            return true
        }

        /// Submits the current guess. `isValidWord` decides dictionary membership; the answer is
        /// always accepted.
        public mutating func submit(isValidWord: (String) -> Bool = WordLists.isValidGuess) throws(SubmitError) -> Guess {
            guard status == .playing else { throw .gameOver }
            guard current.count == WordGuess.wordLength else { throw .tooShort }
            guard current == answer || isValidWord(current) else { throw .notInWordList }
            if hardMode, let message = WordGuess.hardModeViolation(for: current, previous: guesses) {
                throw .mustUseHint(message)
            }
            let guess = Guess(word: current, states: WordGuess.score(guess: current, answer: answer))
            guesses.append(guess)
            current = ""
            if guess.isCorrect {
                status = .won
            } else if guesses.count >= WordGuess.maxGuesses {
                status = .lost
            }
            return guess
        }

        /// Best known state of each letter across all submitted guesses.
        public var keyboard: [Character: LetterState] {
            var map: [Character: LetterState] = [:]
            for guess in guesses {
                for (letter, state) in zip(guess.word, guess.states) {
                    map[letter] = max(map[letter] ?? .unknown, state)
                }
            }
            return map
        }
    }
}
