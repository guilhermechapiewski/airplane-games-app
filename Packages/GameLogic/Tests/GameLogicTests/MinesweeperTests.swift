import Foundation
import Testing
@testable import GameLogic

@Suite("Minesweeper")
struct MinesweeperTests {
    typealias M = Minesweeper

    func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }

    @Test(arguments: M.Level.allCases)
    func levelDimensions(level: M.Level) {
        let s = M.State(level: level, seed: 1)
        #expect(s.rows == level.rows && s.cols == level.cols && s.mineCount == level.mines)
        #expect(s.status == .ready)
        #expect(!s.hasMines)
        #expect(s.minePoints.isEmpty)
        #expect(s.minesLeft == level.mines)
    }

    @Test func classicSizes() {
        #expect((M.Level.beginner.rows, M.Level.beginner.cols, M.Level.beginner.mines) == (9, 9, 10))
        #expect((M.Level.intermediate.rows, M.Level.intermediate.cols, M.Level.intermediate.mines) == (16, 16, 40))
        #expect((M.Level.expert.rows, M.Level.expert.cols, M.Level.expert.mines) == (30, 16, 99))
    }

    @Test(arguments: M.Level.allCases)
    func firstTapIsAlwaysSafeAndOpensAnArea(level: M.Level) {
        var rng = SeededRandom(seed: 99)
        for seed in UInt64(0)..<300 {
            var s = M.State(level: level, seed: seed)
            let tap = p(Int.random(in: 0..<level.rows, using: &rng), Int.random(in: 0..<level.cols, using: &rng))
            let outcome = s.reveal(tap)
            #expect(outcome.exploded == nil)
            #expect(s.minePoints.count == level.mines)
            #expect(!s[tap].isMine)
            #expect(s[tap].adjacent == 0, "first tap must open an area")
            #expect(s.neighbors(of: tap).allSatisfy { !s[$0].isMine })
            #expect(outcome.revealed.count > 1 || s.status == .won)
            #expect(s.status == .playing || s.status == .won)
        }
    }

    @Test func generationIsDeterministicPerSeed() {
        var a = M.State(level: .intermediate, seed: 42)
        var b = M.State(level: .intermediate, seed: 42)
        var c = M.State(level: .intermediate, seed: 43)
        a.reveal(p(5, 5)); b.reveal(p(5, 5)); c.reveal(p(5, 5))
        #expect(a == b)
        #expect(a.minePoints != c.minePoints)
    }

    @Test func crowdedBoardStillKeepsFirstCellSafe() {
        // 3x3 with 8 mines: no room for a safe neighbourhood, only the tapped cell is guaranteed.
        var s = M.State(rows: 3, cols: 3, mines: 8, seed: 5)
        let outcome = s.reveal(p(1, 1))
        #expect(outcome.exploded == nil)
        #expect(s[p(1, 1)].adjacent == 8)
        #expect(s.status == .won)
    }

    @Test func adjacencyCounts() {
        let s = M.State(rows: 3, cols: 3, mines: [p(0, 0), p(2, 2)])
        #expect(s[p(1, 1)].adjacent == 2)
        #expect(s[p(0, 1)].adjacent == 1)
        #expect(s[p(0, 2)].adjacent == 0)
        #expect(s[p(2, 1)].adjacent == 1)
    }

    @Test func floodFillRevealsZerosAndBorderNumbers() {
        // Mine in the corner of a 4x4: everything but the mine opens from the far corner.
        var s = M.State(rows: 4, cols: 4, mines: [p(0, 0)])
        let outcome = s.reveal(p(3, 3))
        #expect(outcome.revealed.count == 15)
        #expect(outcome.revealed.first == p(3, 3))
        #expect(s.status == .won)
        #expect(s[p(0, 0)].isFlagged, "winning flags remaining mines")
        #expect(s.minesLeft == 0)
    }

    @Test func floodFillStopsAtNumbersAndFlags() {
        // Column of mines at col 2 splits the board.
        let mines: Set<GridPoint> = [p(0, 2), p(1, 2), p(2, 2), p(3, 2)]
        var s = M.State(rows: 4, cols: 5, mines: mines)
        s.toggleFlag(p(3, 0))
        let outcome = s.reveal(p(0, 0))
        #expect(Set(outcome.revealed) == [p(0, 0), p(1, 0), p(2, 0), p(0, 1), p(1, 1), p(2, 1), p(3, 1)])
        #expect(s[p(3, 0)].isFlagged)
        #expect(s[p(0, 4)].mark == .hidden)
        #expect(s.status == .playing)
    }

    @Test func revealingNumberDoesNotFlood() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0)])
        let outcome = s.reveal(p(1, 1))
        #expect(outcome.revealed == [p(1, 1)])
        #expect(s.revealedCount == 1)
    }

    @Test func hittingAMineLoses() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0), p(2, 2)])
        s.toggleFlag(p(1, 1))
        let outcome = s.reveal(p(0, 0))
        #expect(outcome.exploded == p(0, 0))
        #expect(s.status == .lost)
        #expect(s.exploded == p(0, 0))
        #expect(s.wrongFlags == [p(1, 1)])
        // Game over: further actions do nothing.
        let late = s.reveal(p(0, 2))
        #expect(late.isEmpty)
        let flagged = s.toggleFlag(p(0, 2))
        #expect(!flagged)
    }

    @Test func flagsToggleAndBlockReveal() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0)])
        var changed = s.toggleFlag(p(0, 0))
        #expect(changed)
        #expect(s[p(0, 0)].isFlagged)
        #expect(s.minesLeft == 0)
        let blocked = s.reveal(p(0, 0))
        #expect(blocked.isEmpty, "flagged cells can't be revealed")
        changed = s.toggleFlag(p(0, 0))
        #expect(changed)
        #expect(s[p(0, 0)].mark == .hidden)
        s.reveal(p(2, 2))
        changed = s.toggleFlag(p(2, 2))
        #expect(!changed, "revealed cells can't be flagged")
    }

    @Test func minesLeftCanGoNegative() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0)])
        s.toggleFlag(p(0, 1)); s.toggleFlag(p(0, 2))
        #expect(s.minesLeft == -1)
    }

    @Test func flaggingBeforeFirstRevealIsAllowedAndKept() {
        var s = M.State(level: .beginner, seed: 3)
        s.toggleFlag(p(0, 0))
        s.reveal(p(8, 8))
        #expect(s[p(0, 0)].isFlagged, "flood fill never removes flags")
        #expect(s.status != .ready)
    }

    @Test func chordRevealsNeighboursWhenFlagsMatch() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0)])
        s.reveal(p(0, 1))
        #expect(!s.canChord(at: p(0, 1)), "no flag yet")
        let noop684 = s.chord(p(0, 1))
        #expect(noop684.isEmpty)
        s.toggleFlag(p(0, 0))
        #expect(s.canChord(at: p(0, 1)))
        let outcome = s.chord(p(0, 1))
        #expect(outcome.exploded == nil)
        #expect(outcome.revealed.count == 7)
        #expect(s.status == .won)
    }

    @Test func chordWithWrongFlagExplodes() {
        var s = M.State(rows: 3, cols: 3, mines: [p(0, 0)])
        s.reveal(p(0, 1))
        s.toggleFlag(p(0, 2))
        let outcome = s.chord(p(0, 1))
        #expect(outcome.exploded == p(0, 0))
        #expect(s.status == .lost)
        #expect(s.wrongFlags == [p(0, 2)])
    }

    @Test func chordIgnoresZerosAndHiddenCells() {
        var s = M.State(rows: 3, cols: 4, mines: [p(0, 0)])
        #expect(!s.canChord(at: p(2, 3)))
        s.reveal(p(2, 3))
        #expect(s[p(2, 3)].adjacent == 0)
        #expect(!s.canChord(at: p(2, 3)))
    }

    @Test func winRequiresAllSafeCells() {
        var s = M.State(rows: 2, cols: 2, mines: [p(0, 0)])
        s.reveal(p(0, 1)); s.reveal(p(1, 0))
        #expect(s.status == .playing)
        s.reveal(p(1, 1))
        #expect(s.status == .won)
        #expect(s.wrongFlags.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var s = M.State(level: .expert, seed: 77)
        s.reveal(p(15, 8))
        s.toggleFlag(p(0, 0))
        let data = try JSONEncoder().encode(s)
        var decoded = try JSONDecoder().decode(M.State.self, from: data)
        #expect(decoded == s)
        // Continues identically after decoding.
        let next = s.allPoints.first { s[$0].mark == .hidden && !s[$0].isMine }!
        let x = decoded.reveal(next), y = s.reveal(next)
        #expect(x == y)
    }

    @Test func randomPlaythroughsNeverRevealMinesBySafeMoves() {
        // Revealing only safe cells always ends in a win with every mine flagged.
        for seed in UInt64(0)..<20 {
            var s = M.State(level: .intermediate, seed: seed)
            s.reveal(p(8, 8))
            while s.status == .playing {
                let next = s.allPoints.first { s[$0].mark == .hidden && !s[$0].isMine }!
                let o = s.reveal(next)
                #expect(o.exploded == nil)
            }
            #expect(s.status == .won)
            #expect(s.minesLeft == 0)
        }
    }
}
