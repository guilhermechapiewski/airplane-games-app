import Foundation
import Testing
@testable import GameLogic

@Suite("Word Guess hints")
struct WordGuessHintTests {
    typealias G = WordGuess

    private func play(_ words: [String], answer: String, hard: Bool = false) -> G.State {
        var s = G.State(answer: answer, hardMode: hard)
        for w in words {
            for ch in w { s.type(ch) }
            _ = try? s.submit()
        }
        return s
    }

    @Test func patternMatchesScore() {
        let words = ["crane", "eerie", "speed", "abbey", "llama", "taste", "geese", "allot", "level", "stall"]
        for g in words {
            for a in words {
                let code = G.pattern(Array(g.utf8).map { $0 - 97 }, Array(a.utf8).map { $0 - 97 })
                var expected = 0, place = 1
                for s in G.score(guess: g, answer: a) {
                    expected += (s == .correct ? 2 : s == .present ? 1 : 0) * place
                    place *= 3
                }
                #expect(code == expected, "\(g) vs \(a)")
            }
        }
    }

    @Test func openerIsAStrongCommonWord() throws {
        let s = try #require(G.suggestion(after: [], hardMode: false))
        #expect(s.kind == .opener)
        #expect(s.remaining == WordLists.answers.count)
        #expect(Set(s.word).count == 5, "an opener tries five different letters: \(s.word)")
        #expect(WordLists.answers.contains(s.word))
        #expect(s.newLetters.count == 3)
        #expect(s.explanation.contains(s.word.uppercased()))
        #expect(G.suggestion(after: [], hardMode: false)?.word == s.word, "deterministic")
    }

    @Test(arguments: [("crane", ["slate"]), ("ghost", ["audio", "trend"]), ("pizza", ["house"]),
                      ("knoll", ["crane", "boils"]), ("lunch", ["irate"])])
    func suggestionFitsEveryClue(answer: String, guesses: [String]) throws {
        let state = play(guesses, answer: answer)
        #expect(state.guesses.count == guesses.count)
        let s = try #require(G.suggestion(after: state.guesses, hardMode: false))
        #expect(G.fits(s.word, guesses: state.guesses), "\(s.word) breaks a clue for \(answer)")
        #expect(G.remainingWords(after: state.guesses, answers: WordLists.answers, allWords: []).contains(answer))
        if s.kind == .narrow {
            #expect(s.remaining > 1)
            #expect(s.expectedLeft < Double(s.remaining))
            #expect(s.explanation.hasPrefix("\(s.remaining) words still fit"))
        } else {
            #expect(s.kind == .onlyOne)
            #expect(s.word == answer)
        }
    }

    @Test(arguments: [("crane", ["trace"]), ("baker", ["cater", "water"]), ("spoon", ["stone"])])
    func respectsHardMode(answer: String, guesses: [String]) throws {
        let state = play(guesses, answer: answer, hard: true)
        #expect(state.guesses.count == guesses.count)
        let s = try #require(G.suggestion(after: state.guesses, hardMode: true))
        #expect(G.hardModeViolation(for: s.word, previous: state.guesses) == nil)
        // A hard-mode game accepts it.
        var next = state
        for ch in s.word { next.type(ch) }
        #expect((try? next.submit()) != nil)
    }

    @Test func onlyOneWordFitsNamesIt() throws {
        let state = play(["crate"], answer: "crane")
        let s = try #require(G.suggestion(after: state.guesses, hardMode: false, answers: ["crane", "crate", "grape"]))
        #expect(s.kind == .onlyOne)
        #expect(s.word == "crane")
        #expect(s.title == "Only one word fits!")
        #expect(s.explanation == "Every clue points to CRANE.")
    }

    @Test func prefersTheGuessThatSplitsBest() throws {
        // Brute force: no other fitting word leaves fewer answers on average.
        let pool = ["crane", "crate", "trace", "react", "caret", "cater", "grace", "brace", "tract", "carte"]
        let best = try #require(G.suggestion(after: [], hardMode: false, answers: pool))
        func expected(_ g: String) -> Double {
            let groups = Dictionary(grouping: pool) { G.score(guess: g, answer: $0) }
            return Double(groups.values.reduce(0) { $0 + $1.count * $1.count }) / Double(pool.count)
        }
        #expect(abs(best.expectedLeft - expected(best.word)) < 1e-9)
        #expect(pool.allSatisfy { expected($0) >= best.expectedLeft - 1e-9 })
        // Seven words that differ only in the first letter: any guess leaves 1 (if right) or 6.
        let ills = ["bills", "fills", "hills", "kills", "mills", "pills", "wills"]
        let s = try #require(G.suggestion(after: [], hardMode: false, answers: ills))
        #expect(abs(s.expectedLeft - 37.0 / 7.0) < 1e-9)
    }

    @Test func friendsWordFallsBackToAllWords() throws {
        let secret = try #require(WordLists.validGuesses.sorted().first { !WordLists.answers.contains($0) && $0.hasPrefix("xy") })
        let state = play(["sally", "crone"], answer: secret)
        let all = WordLists.validGuesses.sorted()
        let s = try #require(G.suggestion(after: state.guesses, hardMode: false, allWords: all))
        #expect(G.fits(s.word, guesses: state.guesses))
    }

    @Test func friendsWordIsNeverRuledOut() throws {
        // ABAFT isn't a common answer; SHAFT is the only common answer that fits these clues, but
        // the friend's word could be any valid word, so the hint mustn't claim it's the only one.
        let state = play(["crane", "pilot"], answer: "abaft")
        let all = WordLists.validGuesses.sorted()
        let s = try #require(G.suggestion(after: state.guesses, hardMode: false, allWords: all))
        #expect(s.kind == .narrow)
        #expect(s.remaining == all.filter { G.fits($0, guesses: state.guesses) }.count)
        #expect(s.remaining > 1)
    }

    @Test func isFastEnough() {
        let start = threadCPUTime()
        _ = G.suggestion(after: [], hardMode: false)
        let state = play(["irate"], answer: "lunch")
        _ = G.suggestion(after: state.guesses, hardMode: false)
        #expect(threadCPUTime() - start < 1.0)
    }
}
