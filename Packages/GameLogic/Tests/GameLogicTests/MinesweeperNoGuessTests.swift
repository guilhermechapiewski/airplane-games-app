import Foundation
import Testing
@testable import GameLogic

@Suite("Minesweeper no-guess")
struct MinesweeperNoGuessTests {
    typealias M = Minesweeper

    func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }

    // MARK: Solver

    @Test func solverClearsABoardThatNeedsOnlyLogic() {
        // [start][1][mine]: the 1 has a single hidden neighbour, so it must be the mine.
        let board = M.State(rows: 1, cols: 3, mines: [p(0, 2)])
        #expect(M.Solver.solvesWithoutGuessing(board, from: p(0, 0)))
    }

    @Test func solverRejectsAFiftyFifty() {
        // Two hidden cells share one mine and every clue sees both: a coin flip.
        let board = M.State(rows: 2, cols: 3, mines: [p(0, 2)])
        #expect(!M.Solver.solvesWithoutGuessing(board, from: p(0, 0)))
    }

    @Test func solverUsesOverlappingClues() {
        // Top row 1 2 1 over a hidden bottom row with mines at both ends (the classic 1-2-1).
        // No single clue decides anything; comparing neighbouring clues does.
        let board = M.State(rows: 2, cols: 3, mines: [p(1, 0), p(1, 2)])
        #expect(M.Solver.solvesWithoutGuessing(board, opened: [p(0, 0), p(0, 1), p(0, 2)]))
    }

    @Test func solverNeedsTheCluesToDecide() {
        // Row 0: [ . ][ 1 ][ ? ]   Row 1: [ . ][ 1 ][ ? ]  with one mine at (0,2).
        // Both 1s see both hidden cells, so they leave a coin flip...
        let board = M.State(rows: 2, cols: 3, mines: [p(0, 2)])
        let open = [p(0, 0), p(0, 1), p(1, 0), p(1, 1)]
        #expect(!M.Solver.solvesWithoutGuessing(board, opened: open))
        // ...but when both hidden cells are mines, the clues read 2 and settle it.
        let full = M.State(rows: 2, cols: 3, mines: [p(0, 2), p(1, 2)])
        #expect(M.Solver.solvesWithoutGuessing(full, opened: open))
    }

    // MARK: Generation

    @Test(arguments: M.Level.allCases)
    func everyGeneratedBoardIsSolvableWithoutGuessing(level: M.Level) {
        var rng = SeededRandom(seed: 7)
        let boards = level == .expert ? 40 : 120
        for seed in UInt64(0)..<UInt64(boards) {
            var s = M.State(level: level, seed: seed)
            let tap = p(Int.random(in: 0..<level.rows, using: &rng), Int.random(in: 0..<level.cols, using: &rng))
            s.reveal(tap)
            #expect(s.minePoints.count == level.mines)
            #expect(s.neighbors(of: tap).allSatisfy { !s[$0].isMine }, "the first tap still opens an area")
            let fresh = M.State(rows: s.rows, cols: s.cols, mines: Set(s.minePoints))
            #expect(M.Solver.solvesWithoutGuessing(fresh, from: tap), "\(level) seed \(seed) needs a guess")
        }
    }

    @Test func noGuessGenerationIsDeterministicPerSeed() {
        var a = M.State(level: .expert, seed: 11)
        var b = M.State(level: .expert, seed: 11)
        a.reveal(p(15, 8)); b.reveal(p(15, 8))
        #expect(a == b)
    }

    @Test func expertGenerationIsFast() {
        let start = threadCPUTime()
        for seed in UInt64(100)..<106 {
            var s = M.State(level: .expert, seed: seed)
            s.reveal(p(0, 0)) // a corner tap: the hardest start
        }
        // Generous for unoptimized test builds; optimized builds are far faster.
        #expect((threadCPUTime() - start) / 6 < 1.0)
    }
}
