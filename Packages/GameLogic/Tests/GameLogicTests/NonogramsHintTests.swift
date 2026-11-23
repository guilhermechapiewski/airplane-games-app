import Foundation
import Testing
@testable import GameLogic

@Suite("Nonograms explained hints")
struct NonogramsHintTests {
    typealias N = Nonograms

    func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }
    static let heart = NonogramsTests.heart

    @Test func aDeductionNamesItsLineAndClue() throws {
        let hint = try #require(N.Board(for: Self.heart).explainedHint(for: Self.heart))
        #expect(hint.kind == .deduction)
        let line = try #require(hint.line)
        #expect(line.cells(width: 5, height: 5).contains(hint.point))
        // Rows 1-2 are full (clue 5), so the explanation quotes that clue.
        #expect(line == .row(1))
        #expect(hint.title == "Row 2")
        #expect(hint.explanation.contains("5"))
        #expect(hint.mark == .filled)
        #expect(!hint.explanation.contains("already marked"), "a blank board needs no earlier marks")
    }

    @Test func earlierMarksAreMentionedWhenTheyMatter() throws {
        // Row 0 is ".#.#." (clue 1 1). With columns 1 and 3 known filled, the row's ends become
        // decidable only because of those marks.
        var b = N.Board(for: Self.heart)
        b[p(0, 1)] = .filled
        b[p(0, 3)] = .filled
        b[p(1, 0)] = .filled; b[p(1, 1)] = .filled; b[p(1, 2)] = .filled; b[p(1, 3)] = .filled; b[p(1, 4)] = .filled
        b[p(2, 0)] = .filled; b[p(2, 1)] = .filled; b[p(2, 2)] = .filled; b[p(2, 3)] = .filled; b[p(2, 4)] = .filled
        let hint = try #require(b.explainedHint(for: Self.heart))
        if hint.line == .row(0) {
            #expect(hint.explanation.contains("already marked"))
        }
        #expect(hint.mark == (Self.heart[hint.point] ? .filled : .crossed))
    }

    @Test func aMistakeIsPointedOutWithoutGivingTheAnswerAway() throws {
        var b = N.Board(for: Self.heart)
        b[p(0, 0)] = .filled
        let hint = try #require(b.explainedHint(for: Self.heart))
        #expect(hint.kind == .mistake)
        #expect(hint.point == p(0, 0))
        #expect(hint.mark == .crossed)
        #expect(hint.title == "Check This Square")
    }

    @Test func explainedHintsSolveEveryPuzzle() {
        for puzzle in N.library {
            var b = N.Board(for: puzzle)
            var steps = 0
            while !b.isSolved(puzzle), let hint = b.explainedHint(for: puzzle), steps < puzzle.solution.count * 2 {
                #expect(!hint.explanation.isEmpty)
                #expect(hint.mark == (puzzle[hint.point] ? .filled : .crossed))
                b[hint.point] = hint.mark
                steps += 1
            }
            #expect(b.isSolved(puzzle), "\(puzzle.title)")
        }
    }
}
