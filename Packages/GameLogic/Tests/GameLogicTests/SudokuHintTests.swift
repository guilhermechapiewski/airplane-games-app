import Foundation
import Testing
@testable import GameLogic

@Suite("Sudoku explained hints")
struct SudokuHintTests {
    typealias S = Sudoku

    static let puzzle = SudokuTests.puzzle
    static let solution = SudokuTests.solution

    func newGame() -> S.Game {
        S.Game(puzzle: S.Puzzle(givens: Self.puzzle, solution: Self.solution, difficulty: .easy))
    }

    @Test func lastPossibleNumberNamesTheDigitAndShowsThePeers() throws {
        let hint = try #require(newGame().nextHint())
        #expect(hint.kind == .deduction)
        #expect(hint.technique == .nakedSingle)
        #expect(hint.title == "Last Possible Number")
        #expect(hint.explanation.contains("\(hint.digit)"))
        #expect(Set(hint.area) == Set(S.peers[hint.cell]))
        // Its row, column and box hold every other digit.
        let seen = Set(S.peers[hint.cell].map { Self.puzzle[$0] }).subtracting([0])
        #expect(seen == Set(1...9).subtracting([hint.digit]))
    }

    @Test func onlySpotLeftPointsAtTheUnitAndTheBlockingDigits() throws {
        var found = false
        for seed in UInt64(1)...20 where !found {
            var g = S.Game(puzzle: S.generate(difficulty: .medium, seed: seed))
            while !g.isSolved, let hint = g.nextHint() {
                if hint.technique == .hiddenSingle, let unit = hint.unit, !hint.blockers.isEmpty {
                    found = true
                    #expect(hint.title == "Only Spot Left")
                    #expect(Set(hint.area) == Set(unit.cells))
                    #expect(unit.cells.contains(hint.cell))
                    #expect(hint.explanation.contains("\(hint.digit)"))
                    // Every other empty cell of the unit sees one of the blocking digits.
                    for other in unit.cells where other != hint.cell && g.values[other] == 0 {
                        #expect(hint.blockers.contains { S.areSeen($0, other) && g.values[$0] == hint.digit })
                    }
                    for b in hint.blockers { #expect(g.values[b] == hint.digit) }
                    break
                }
                g.fill(hint)
            }
        }
        #expect(found, "no hidden single met in 20 medium puzzles")
    }

    @Test func aWrongDigitIsPointedOutFirst() throws {
        var g = newGame()
        let cell = try #require((0..<81).first { Self.puzzle[$0] == 0 })
        let wrong = Self.solution[cell] % 9 + 1
        g.enter(wrong, at: cell)
        let hint = try #require(g.nextHint())
        #expect(hint.kind == .mistake)
        #expect(hint.cell == cell)
        #expect(hint.digit == Self.solution[cell])
        #expect(hint.explanation.contains("\(wrong)"))
        g.fill(hint)
        #expect(g.values[cell] == Self.solution[cell])
    }

    @Test func explainingCountsTheHintAndFillingDoesNot() throws {
        var g = newGame()
        let revealed = g.revealHint()
        let hint = try #require(revealed)
        #expect(g.hintsUsed == 1)
        #expect(g.values[hint.cell] == 0, "explaining doesn't fill the square")
        let outcome = g.fill(hint)
        #expect(outcome != nil)
        #expect(g.values[hint.cell] == hint.digit)
        #expect(g.hinted.contains(hint.cell))
        #expect(g.hintsUsed == 1)
        #expect(g.fill(hint) == nil, "filling twice does nothing")
    }

    @Test func everyHintExplainsItselfAcrossDifficulties() {
        for d in Difficulty.allCases {
            var g = S.Game(puzzle: S.generate(difficulty: d, seed: 3))
            while !g.isSolved, let hint = g.revealHint() {
                #expect(!hint.title.isEmpty && !hint.explanation.isEmpty)
                #expect(hint.digit == g.puzzle.solution[hint.cell])
                #expect(hint.area.allSatisfy { (0..<81).contains($0) })
                g.fill(hint)
            }
            #expect(g.isSolved)
        }
    }
}
