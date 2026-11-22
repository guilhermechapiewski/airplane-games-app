import Foundation

/// Bundled English word data shared by the word games.
///
/// Lists are loaded lazily from the package's resource bundle on first use and cached.
/// Swift `static let` initialization is lazy and thread-safe, so every accessor here
/// can be called from any thread or actor.
/// See `Resources/WORDLISTS.md` for sources and licenses.
public enum WordLists {
    /// Every accepted 5-letter guess (lowercase a–z), including plurals and inflections.
    public static var validGuesses: Set<String> { Cache.guesses }

    /// Curated, familiar 5-letter words the computer may choose as a secret (sorted, clean).
    public static var answers: [String] { Cache.answers }

    /// Offensive words never chosen by the computer.
    public static var blocklist: Set<String> { Cache.blocklist }

    /// `true` if `word` (any case) is an accepted 5-letter guess.
    public static func isValidGuess(_ word: String) -> Bool {
        validGuesses.contains(word.lowercased())
    }

    /// A random curated answer.
    public static func randomAnswer<R: RandomNumberGenerator>(using rng: inout R) -> String {
        answers.randomElement(using: &rng) ?? "plane"
    }

    /// `true` if no word in `text` is on the blocklist.
    /// Words are split on anything that is not a letter, so "ice-cream" checks "ice" and "cream",
    /// and the letters-only joined form is checked too.
    public static func isClean(_ text: String) -> Bool {
        let lower = text.lowercased()
        let parts = lower.split { !$0.isLetter }.map(String.init)
        let joined = parts.joined()
        if blocklist.contains(joined) { return false }
        return !parts.contains { blocklist.contains($0) }
    }

    private enum Cache {
        static let guesses: Set<String> = Set(load("guesses5")).union(answers)
        static let answers: [String] = load("answers5").filter { !blocklist.contains($0) }
        static let blocklist: Set<String> = Set(load("blocklist"))

        static func load(_ name: String) -> [String] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                assertionFailure("Missing word list \(name).txt")
                return []
            }
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        }
    }
}
