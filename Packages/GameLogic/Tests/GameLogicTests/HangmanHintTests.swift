import Foundation
import Testing
@testable import GameLogic

@Suite("Hangman hints")
struct HangmanHintTests {
    typealias H = Hangman

    private let pool = ["tiger", "timer", "tuner", "toast", "lion", "panda", "polar bear"]

    @Test func candidatesMatchTheBoard() {
        var s = H.State(phrase: "tiger")
        for c in "tro" { s.guess(c) }
        // T _ _ _ R, no O: tiger, timer, tuner.
        #expect(H.candidates(for: s, in: pool) == ["tiger", "timer", "tuner"])
        s.guess("e")
        #expect(H.candidates(for: s, in: pool) == ["tiger", "timer", "tuner"])
        s.guess("i")
        #expect(H.candidates(for: s, in: pool) == ["tiger", "timer"])
    }

    @Test func aGuessedLetterCannotHideInABlank() {
        var s = H.State(phrase: "toast")
        s.guess("t")
        // T _ _ _ T: "tatty" has a T in a blank, so it can't be the answer.
        #expect(H.candidates(for: s, in: ["toast", "tatty", "trust", "tiger"]) == ["toast", "trust"])
    }

    @Test func phrasesKeepTheirShape() {
        let s = H.State(phrase: "polar bear")
        #expect(H.candidates(for: s, in: pool) == ["polar bear"])
    }

    @Test func suggestsTheMostCommonLetterAmongFits() throws {
        var s = H.State(phrase: "tiger")
        for c in "tro" { s.guess(c) }
        let hint = try #require(H.suggestLetter(for: s, entries: pool))
        #expect(hint.letter == "e")
        #expect(hint.fitting == 3)
        #expect(hint.containing == 3)
        #expect(hint.title == "Try E")
        #expect(hint.explanation == "E is in all 3 words that still fit — a safe pick.")
    }

    @Test func explainsHowManyWordsHaveTheLetter() throws {
        var s = H.State(phrase: "tiger")
        for c in "tre" { s.guess(c) }
        let hint = try #require(H.suggestLetter(for: s, entries: pool))
        // tiger and timer have an I; tuner has a U and an N.
        #expect(hint.letter == "i")
        #expect(hint.explanation == "I appears in 2 of the 3 words that still fit.")
    }

    @Test func fallsBackToEnglishFrequency() throws {
        var s = H.State(phrase: "quiz night")
        let first = try #require(H.suggestLetter(for: s, entries: []))
        #expect(first.letter == "e")
        #expect(first.fitting == 0)
        #expect(first.explanation.contains("most common letter in English"))
        for c in "eta" { s.guess(c) }
        #expect(H.suggestLetter(for: s, entries: pool)?.letter == "o")
    }

    @Test func noHintWhenOver() {
        var s = H.State(phrase: "ox")
        s.guess("o")
        s.guess("x")
        #expect(s.status == .won)
        #expect(H.suggestLetter(for: s, entries: pool) == nil)
    }

    @Test func followingHintsAlwaysUsesOnlyPublicInfo() throws {
        for category in WordCategory.all {
            for entry in category.entries.prefix(12) where H.problem(with: entry) == nil {
                var s = H.State(phrase: entry, category: category.title)
                while s.status == .playing {
                    let hint = try #require(H.suggestLetter(for: s, entries: category.entries))
                    #expect(!s.guessed.contains(hint.letter))
                    #expect(hint.fitting >= 1, "the answer itself always fits")
                    #expect(hint.containing >= 1)
                    s.guess(hint.letter)
                }
                // Hints only suggest letters from fitting words, so a hint-led game never loses here.
                #expect(s.status == .won, "\(entry)")
            }
        }
    }
}
