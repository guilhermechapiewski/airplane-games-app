import Foundation
import Testing
@testable import GameLogic

@Suite("Word Guess")
struct WordGuessTests {
    typealias G = WordGuess
    typealias L = WordGuess.LetterState

    /// Parses a pattern like "CP.A." — C correct, P present, . or A absent.
    private func pattern(_ p: String) -> [L] {
        p.map { $0 == "C" ? .correct : $0 == "P" ? .present : .absent }
    }

    private func submitError(_ s: inout G.State, valid: Bool? = nil) -> G.SubmitError? {
        do {
            if let valid { _ = try s.submit(isValidWord: { _ in valid }) } else { _ = try s.submit() }
            return nil
        } catch {
            return error
        }
    }

    private func state(_ answer: String, hard: Bool = false, guesses: [String] = []) throws -> G.State {
        var s = G.State(answer: answer, hardMode: hard)
        for word in guesses {
            for ch in word { s.type(ch) }
            _ = try s.submit(isValidWord: { _ in true })
        }
        return s
    }

    @Test(arguments: [
        ("crane", "crane", "CCCCC"),
        ("crane", "slope", "....C"),
        ("crane", "react", "PPCP."),
        // Duplicate letters in the guess: only as many marks as the answer has copies.
        ("abbey", "kebab", ".PCPP"),
        ("abbey", "babes", "PPCC."),
        ("robot", "boost", "PCP.C"),
        ("hello", "lllll", "..CC."),
        ("apple", "paper", "PPCP."),
        ("crane", "eerie", "..P.C"),
        // Exact match takes priority over an earlier present.
        ("spool", "loops", "PPCPP"),
        ("those", "geese", "...CC"),
        ("lever", "eerie", "PCP.."),
        ("ample", "lapel", "PPCP."),
        ("sassy", "assss", "PPCC."),
        ("mamma", "amass", "PPP.."),
    ])
    func scoringHandlesDuplicates(answer: String, guess: String, expected: String) {
        #expect(G.score(guess: guess, answer: answer) == pattern(expected), "\(guess) vs \(answer)")
    }

    @Test func scoringIsCaseInsensitive() {
        #expect(G.score(guess: "CRANE", answer: "crane") == pattern("CCCCC"))
    }

    @Test func presentCountNeverExceedsAnswerCopies() {
        var rng = SeededRandom(seed: 99)
        let words = WordLists.answers
        for _ in 0..<2_000 {
            let answer = words.randomElement(using: &rng)!, guess = words.randomElement(using: &rng)!
            let states = G.score(guess: guess, answer: answer)
            for letter in Set(guess) {
                let marked = zip(guess, states).filter { $0.0 == letter && $0.1 != .absent }.count
                let copies = answer.filter { $0 == letter }.count
                #expect(marked == min(copies, guess.filter { $0 == letter }.count))
            }
            for (i, (g, a)) in zip(guess, answer).enumerated() {
                #expect((states[i] == .correct) == (g == a))
            }
        }
    }

    @Test func typingAndDeleting() {
        var s = G.State(answer: "crane")
        let r1 = s.deleteLetter()
        #expect(!r1)
        for ch in "abcdef" { s.type(ch) }
        #expect(s.current == "abcde")
        let r2 = s.type("z")
        #expect(!r2)
        let r3 = s.type("1")
        #expect(!r3)
        let r4 = s.deleteLetter()
        #expect(r4)
        #expect(s.current == "abcd")
        s.type("Q")
        #expect(s.current == "abcdq")
        #expect(s.hasProgress)
    }

    @Test func rejectsNonLetters() {
        var s = G.State(answer: "crane")
        let r5 = s.type(" ")
        #expect(!r5)
        let r6 = s.type("é")
        #expect(!r6)
        let r7 = s.type("-")
        #expect(!r7)
        #expect(s.current.isEmpty)
    }

    @Test func tooShortAndInvalidWords() {
        var s = G.State(answer: "crane")
        for ch in "cra" { s.type(ch) }
        let r8 = submitError(&s)
        #expect(r8 == G.SubmitError.tooShort)
        for ch in "zz" { s.type(ch) }
        let r9 = submitError(&s)
        #expect(r9 == G.SubmitError.notInWordList)
        #expect(s.current == "crazz", "an invalid guess keeps the typed letters")
        #expect(s.guesses.isEmpty)
    }

    @Test func answerIsAlwaysAccepted() throws {
        var s = G.State(answer: "xyzzy")
        for ch in "xyzzy" { s.type(ch) }
        let guess = try s.submit(isValidWord: { _ in false })
        #expect(guess.isCorrect)
        #expect(s.status == .won)
    }

    @Test func winAndLoss() throws {
        var won = try state("crane", guesses: ["slope", "crane"])
        #expect(won.status == .won)
        let r10 = won.type("a")
        #expect(!r10)
        let r11 = submitError(&won)
        #expect(r11 == G.SubmitError.gameOver)

        let lost = try state("crane", guesses: ["slope", "slope", "slope", "slope", "slope", "slope"])
        #expect(lost.status == .lost)
        #expect(lost.guesses.count == 6)
        #expect(lost.isOver)
    }

    @Test func realWordListIsUsedByDefault() throws {
        var s = G.State(answer: "crane")
        for ch in "plane" { s.type(ch) }
        let g = try s.submit()
        #expect(g.states == pattern("..CCC"))
    }

    @Test func keyboardKeepsBestState() throws {
        let s = try state("crane", guesses: ["eerie", "acorn"])
        let k = s.keyboard
        #expect(k["e"] == .correct)   // correct in "eerie"'s last slot
        #expect(k["r"] == .present)
        #expect(k["i"] == .absent)
        #expect(k["a"] == .present)
        #expect(k["c"] == .present)
        #expect(k["n"] == .present)
        #expect(k["z"] == nil)
        // A letter that was absent in one slot (duplicate) but present elsewhere stays present.
        let d = try state("abbey", guesses: ["kebab"])
        #expect(d.keyboard["b"] == .correct)
        #expect(d.keyboard["k"] == .absent)
    }

    @Test func hardModeRequiresCorrectLettersInPlace() throws {
        var s = try state("crane", hard: true, guesses: ["trace"])
        for ch in "brace" { s.type(ch) }
        _ = try s.submit(isValidWord: { _ in true })
        var t = try state("crane", hard: true, guesses: ["trace"])
        for ch in "craft" { t.type(ch) }
        let r12 = submitError(&t, valid: true)
        #expect(r12 == G.SubmitError.mustUseHint("5th letter must be E"))
    }

    @Test func hardModeRequiresPresentLetters() throws {
        var s = try state("crane", hard: true, guesses: ["acorn"])
        for ch in "clone" { s.type(ch) }
        let r13 = submitError(&s, valid: true)
        #expect(r13 == G.SubmitError.mustUseHint("Guess must contain A"))
        s.deleteLetter(); s.deleteLetter(); s.deleteLetter(); s.deleteLetter(); s.deleteLetter()
        for ch in "racon" { s.type(ch) }
        _ = try s.submit(isValidWord: { _ in true })
        #expect(s.guesses.count == 2)
    }

    @Test func hardModeCountsDuplicates() {
        let prior = G.Guess(word: "eerie", states: G.score(guess: "eerie", answer: "levee"))
        // eerie vs levee: e P? Let the scorer decide, then require that many e's.
        let needed = zip(prior.word, prior.states).filter { $0.0 == "e" && $0.1 != .absent }.count
        #expect(needed >= 2)
        #expect(G.hardModeViolation(for: "there", previous: [prior]) != nil)
        #expect(G.hardModeViolation(for: "levee", previous: [prior]) == nil)
    }

    @Test func hardModeIgnoredWhenOff() throws {
        var s = try state("crane", guesses: ["trace"])
        for ch in "moldy" { s.type(ch) }
        _ = try s.submit(isValidWord: { _ in true })
        #expect(s.guesses.count == 2)
    }

    @Test func codableRoundTrip() throws {
        var s = try state("crane", hard: true, guesses: ["slope", "trace"])
        s.type("c")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(G.State.self, from: data)
        #expect(back == s)
        #expect(back.current == "c")
        #expect(back.hardMode)
    }
}
