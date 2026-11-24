/// Hangman hints: the letter most likely to be in the answer, using only what's on screen.
extension Hangman {
    /// English letters from most to least common (in running text).
    public static let englishFrequency: [Character] = Array("etaoinsrhldcumfpgwybvkxjqz")

    /// A suggested letter and why.
    public struct LetterHint: Equatable, Sendable {
        public let letter: Character
        /// Entries from the list that still fit the board (0: the hint fell back to English frequency).
        public let fitting: Int
        /// How many of those contain `letter`.
        public let containing: Int

        public var title: String { "Try \(String(letter).uppercased())" }

        public var explanation: String {
            let l = String(letter).uppercased()
            if fitting == 0 {
                return "\(l) is the most common letter in English that you haven't tried yet."
            }
            if fitting == 1 {
                return "Only one word in this category fits the board, and it has \(article(l)) \(l)."
            }
            if containing == fitting {
                return "\(l) is in all \(fitting) words that still fit — a safe pick."
            }
            return "\(l) appears in \(containing) of the \(fitting) words that still fit."
        }

        private func article(_ letter: String) -> String {
            "AEFHILMNORSX".contains(letter) ? "an" : "a"
        }
    }

    /// Entries (normalized) that match the board: same shape, the same revealed letters, and no
    /// guessed letter in a blank (a correct guess reveals every copy).
    public static func candidates(for state: State, in entries: [String]) -> [String] {
        let pattern = Array(state.masked(placeholder: "_"))
        let guessed = Set(state.guessed)
        return Set(entries.map(normalize)).sorted().filter { entry in
            let chars = Array(entry)
            guard chars.count == pattern.count else { return false }
            for (p, c) in zip(pattern, chars) {
                if p == "_" {
                    if !alphabet.contains(c) || guessed.contains(c) { return false }
                } else if p != c {
                    return false
                }
            }
            return true
        }
    }

    /// The untried letter found in the most entries that still fit (ties: the more common letter
    /// in English). With no fitting entries (a friend's phrase) it falls back to English frequency.
    public static func suggestLetter(for state: State, entries: [String]) -> LetterHint? {
        guard state.status == .playing else { return nil }
        let untried = englishFrequency.filter { !state.guessed.contains($0) }
        guard !untried.isEmpty else { return nil }
        let fits = candidates(for: state, in: entries)
        guard !fits.isEmpty else {
            return LetterHint(letter: untried[0], fitting: 0, containing: 0)
        }
        var best: (letter: Character, count: Int)?
        for letter in untried {   // in frequency order, so the first maximum wins ties
            let count = fits.filter { $0.contains(letter) }.count
            if count > (best?.count ?? 0) { best = (letter, count) }
        }
        guard let best else { return LetterHint(letter: untried[0], fitting: 0, containing: 0) }
        return LetterHint(letter: best.letter, fitting: fits.count, containing: best.count)
    }
}
