import Foundation
import Testing
@testable import GameLogic

@Suite("Hangman")
struct HangmanTests {
    typealias H = Hangman

    @Test func normalizesInput() {
        #expect(H.normalize("  Ice   Cream ") == "ice cream")
        #expect(H.normalize("Café") == "cafe")
        #expect(H.normalize("Rock’n’Roll") == "rock'n'roll")
        #expect(H.normalize("Jack—in—the—box") == "jack-in-the-box")
    }

    @Test func validatesPhrases() {
        #expect(H.problem(with: "hello world") == nil)
        #expect(H.problem(with: "don't stop") == nil)
        #expect(H.problem(with: "x") == .tooShort)
        #expect(H.problem(with: "- -") == .tooShort)
        #expect(H.problem(with: "r2d2") == .invalidCharacters)
        #expect(H.problem(with: "hi!") == .invalidCharacters)
        #expect(H.problem(with: String(repeating: "a", count: 40)) == .tooLong)
    }

    @Test func punctuationAndSpacesAreAutoRevealed() {
        let s = H.State(phrase: "rock-n roll's")
        #expect(s.masked() == "____-_ ____'_")
        #expect(s.letters == Set("rocknlls"))
    }

    @Test func hitsMissesAndRepeats() {
        var s = H.State(phrase: "banana")
        let g1 = s.guess("a")
        #expect(g1 == .hit(count: 3))
        let g2 = s.guess("A")
        #expect(g2 == .ignored)
        let g3 = s.guess("z")
        #expect(g3 == .miss)
        let g4 = s.guess("z")
        #expect(g4 == .ignored)
        let g5 = s.guess("1")
        #expect(g5 == .ignored)
        #expect(s.masked() == "_a_a_a")
        #expect(s.misses == 1)
        #expect(s.livesLeft == 5)
        #expect(s.wrongGuesses == ["z"])
        #expect(s.correctGuesses == ["a"])
    }

    @Test func winRevealsEverything() {
        var s = H.State(phrase: "ice-cream")
        for c in "icream" { s.guess(c) }
        #expect(s.status == .won)
        #expect(s.masked() == "ice-cream")
        let g6 = s.guess("z")
        #expect(g6 == .ignored)
    }

    @Test func loseAfterSixMisses() {
        var s = H.State(phrase: "cat")
        for c in "qwyuio" { s.guess(c) }
        #expect(s.status == .lost)
        #expect(s.livesLeft == 0)
        #expect(s.masked() == "cat", "the word is shown after losing")
        let g7 = s.guess("c")
        #expect(g7 == .ignored)
    }

    @Test func fiveMissesStillPlaying() {
        var s = H.State(phrase: "cat")
        for c in "qwyui" { s.guess(c) }
        #expect(s.status == .playing)
        #expect(s.livesLeft == 1)
        s.guess("c"); s.guess("a"); s.guess("t")
        #expect(s.status == .won)
    }

    @Test func hintIsTrimmed() {
        #expect(H.State(phrase: "cat", hint: "   ").hint == nil)
        #expect(H.State(phrase: "cat", hint: " pet ").hint == "pet")
    }

    @Test func codableRoundTrip() throws {
        var s = H.State(phrase: "polar bear", category: "Animals", hint: "Arctic")
        s.guess("a"); s.guess("x")
        let back = try JSONDecoder().decode(H.State.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.misses == 1)
    }

    @Test func difficultyPoolsSplitByScore() {
        let entries = WordCategory.named("animals")!.entries
        let easy = H.pool(for: .easy, in: entries)
        let medium = H.pool(for: .medium, in: entries)
        let hard = H.pool(for: .hard, in: entries)
        #expect(!easy.isEmpty && !medium.isEmpty && !hard.isEmpty)
        #expect(easy.count + medium.count + hard.count == entries.count)
        let maxEasy = easy.map(H.difficultyScore).max()!
        let minHard = hard.map(H.difficultyScore).min()!
        #expect(maxEasy <= minHard)
        #expect(H.difficultyScore("yak") > H.difficultyScore("rhinoceros"))
    }

    @Test func computerPicksAreCleanValidAndDeterministic() {
        for difficulty in [Difficulty.easy, .medium, .hard] {
            var a = SeededRandom(seed: 3), b = SeededRandom(seed: 3)
            for category in WordCategory.all + [nil] {
                let p1 = H.randomPuzzle(category: category, difficulty: difficulty, using: &a)
                let p2 = H.randomPuzzle(category: category, difficulty: difficulty, using: &b)
                #expect(p1 == p2)
                #expect(H.problem(with: p1.phrase) == nil)
                #expect(WordLists.isClean(p1.phrase))
                if let category { #expect(p1.category == category.title) }
            }
        }
    }

    @Test func everyCategoryEntryIsPlayable() {
        for category in WordCategory.all {
            for entry in category.entries {
                #expect(H.problem(with: entry) == nil, "\(entry) is not playable")
                #expect(H.normalize(entry) == entry)
            }
        }
    }
}
