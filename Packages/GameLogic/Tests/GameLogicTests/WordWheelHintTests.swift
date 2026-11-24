import Foundation
import Testing
@testable import GameLogic

@Suite("Word Wheel hints")
struct WordWheelHintTests {
    typealias W = WordWheel

    private let puzzle = W.Puzzle(center: "a", outer: Array("tnreip"),
                                  answers: ["painter", "paint", "pant", "rant", "train", "tear", "parent"])
    private func any(_: String) -> Bool { true }
    private static func reveal(_ clue: inout W.Clue) -> Bool { clue.revealMore() }

    @Test func cluesRevealProgressively() {
        var clue = W.Clue(word: "parent")
        #expect(clue.title == "A 6-letter word starting with P")
        #expect(clue.pattern == ["p", nil, nil, nil, nil, nil])
        #expect(Self.reveal(&clue))
        #expect(clue.title == "A 6-letter word starting with PA")
        #expect(clue.pattern == ["p", "a", nil, nil, nil, nil])
        #expect(Self.reveal(&clue))
        #expect(clue.title == "A 6-letter word starting with PA and ending in T")
        #expect(clue.pattern == ["p", "a", nil, nil, nil, "t"])
        #expect(clue.spokenPattern == "P, A, blank, blank, blank, T")
        #expect(!clue.canRevealMore)
        #expect(!Self.reveal(&clue))
        #expect(clue.level == W.Clue.maxLevel)
    }

    @Test func articleBeforeEight() {
        #expect(W.Clue(word: "terrapin").title.hasPrefix("An 8-letter word"))
        #expect(W.Clue(word: "pant").title.hasPrefix("A 4-letter word"))
    }

    @Test func nextClueDeepensThenMovesOn() throws {
        var rng = SeededRandom(seed: 7)
        var state = W.State(puzzle: puzzle)
        let first = try #require(state.nextClue(after: nil, using: &rng))
        #expect(first.level == 1)
        #expect(puzzle.answers.contains(first.word))
        let second = try #require(state.nextClue(after: first, using: &rng))
        #expect(second.word == first.word)
        #expect(second.level == 2)
        let third = try #require(state.nextClue(after: second, using: &rng))
        #expect(third.word == first.word)
        #expect(third.level == 3)
        // Fully revealed: the next clue is for another word.
        let fourth = try #require(state.nextClue(after: third, using: &rng))
        #expect(fourth.word != first.word)
        #expect(fourth.level == 1)
        // Finding the hinted word moves on too.
        _ = state.enter(fourth.word, isValidWord: any)
        let fifth = try #require(state.nextClue(after: fourth, using: &rng))
        #expect(fifth.word != fourth.word)
        #expect(!state.found.contains(fifth.word))
    }

    @Test func cluesOnlyForUnfoundAnswers() {
        var rng = SeededRandom(seed: 1)
        var state = W.State(puzzle: puzzle)
        for w in puzzle.answers.dropLast() { _ = state.enter(w, isValidWord: any) }
        for _ in 0..<5 {
            #expect(state.nextClue(after: nil, using: &rng)?.word == puzzle.answers.last)
        }
        // The last word left: after its final clue level the clue stays on it.
        var clue = W.Clue(word: puzzle.answers.last!, level: 3)
        clue = state.nextClue(after: clue, using: &rng)!
        #expect(clue.word == puzzle.answers.last)
        _ = state.enter(puzzle.answers.last!, isValidWord: any)
        #expect(state.nextClue(after: nil, using: &rng) == nil)
    }

    @Test func noCluesOnceFinished() {
        var rng = SeededRandom(seed: 1)
        var state = W.State(puzzle: puzzle)
        state.finish()
        #expect(state.nextClue(after: nil, using: &rng) == nil)
    }

    @Test func hintedWordsScoreNormally() {
        var state = W.State(puzzle: puzzle)
        let clue = W.Clue(word: "parent", level: 3)
        let result = state.enter(clue.word, isValidWord: any)
        #expect((try? result.get())?.points == 6)
    }

    @Test func wordsLeftByLength() {
        var state = W.State(puzzle: puzzle)
        #expect(state.answersLeftByLength == [.init(length: 4, count: 3), .init(length: 5, count: 2),
                                              .init(length: 6, count: 1), .init(length: 7, count: 1)])
        _ = state.enter("painter", isValidWord: any)
        _ = state.enter("rant", isValidWord: any)
        #expect(state.answersLeftByLength == [.init(length: 4, count: 2), .init(length: 5, count: 2),
                                              .init(length: 6, count: 1)])
    }

    @Test func clueRoundTripsThroughCodable() throws {
        var clue = W.Clue(word: "train")
        clue.revealMore()
        let data = try JSONEncoder().encode(clue)
        #expect(try JSONDecoder().decode(W.Clue.self, from: data) == clue)
    }
}
