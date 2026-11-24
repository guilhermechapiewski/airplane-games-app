import Foundation
import Testing
@testable import GameLogic

@Suite("Minesweeper hints")
struct MinesweeperHintTests {
    typealias M = Minesweeper

    /// 3×3 with mines in the top corners, opened from the bottom middle:
    ///
    ///     ? ? ?
    ///     1 2 1
    ///     . . .
    func corners() -> M.State {
        var s = M.State(rows: 3, cols: 3, mines: [GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 2)])
        s.reveal(GridPoint(row: 2, col: 1))
        return s
    }

    @Test func beforeTheFirstTapSuggestsAnywhere() {
        let s = M.State(level: .beginner, seed: 1)
        let hint = s.hint()
        #expect(hint?.kind == .start)
        #expect(hint?.cells == [GridPoint(row: 4, col: 4)])
        #expect(hint?.explanation.contains("always safe") == true)
    }

    @Test func noHintOnceTheGameIsOver() {
        var s = corners()
        s.reveal(GridPoint(row: 0, col: 0))
        #expect(s.status == .lost)
        #expect(s.hint() == nil)
    }

    @Test func overlappingNumbersFindAMine() {
        let hint = corners().hint()
        #expect(hint?.kind == .mine)
        #expect(hint?.cells == [GridPoint(row: 0, col: 2)] || hint?.cells == [GridPoint(row: 0, col: 0)])
        #expect(hint?.clues.count == 2)
    }

    @Test func aSatisfiedNumberMakesItsNeighborsSafe() {
        var s = corners()
        s.toggleFlag(GridPoint(row: 0, col: 0))
        s.toggleFlag(GridPoint(row: 0, col: 2))
        let hint = s.hint()
        #expect(hint?.kind == .safe)
        #expect(hint?.cells == [GridPoint(row: 0, col: 1)])
        #expect(hint?.explanation.hasPrefix("This 1 already touches its mine, so the other squares around it are safe.") == true)
    }

    @Test func flagsAreNotTrustedUntilProven() {
        // A wrong flag on the safe middle square doesn't fool the hint.
        var s = corners()
        s.toggleFlag(GridPoint(row: 0, col: 1))
        let hint = s.hint()
        #expect(hint?.kind == .mine)
        #expect(hint.map { !$0.cells.contains(GridPoint(row: 0, col: 1)) } == true)
    }

    @Test func pointsOutAWrongFlag() {
        var s = corners()
        for c in 0...2 { s.toggleFlag(GridPoint(row: 0, col: c)) }
        let hint = s.hint()
        #expect(hint?.kind == .wrongFlag)
        #expect(hint?.cells == [GridPoint(row: 0, col: 1)])
    }

    @Test func countsTheMinesLeft() {
        // The top-left square is walled in by mines: no number touches it, but once all three
        // mines are flagged, the count says it's safe.
        //     ? M 2
        //     M M 2
        //     2 2 1
        let mines: Set<GridPoint> = [GridPoint(row: 0, col: 1), GridPoint(row: 1, col: 0), GridPoint(row: 1, col: 1)]
        var s = M.State(rows: 3, cols: 3, mines: mines)
        for p in [GridPoint(row: 0, col: 2), GridPoint(row: 1, col: 2), GridPoint(row: 2, col: 0),
                  GridPoint(row: 2, col: 1), GridPoint(row: 2, col: 2)] { s.reveal(p) }
        #expect(s.hint()?.kind == .mine)
        for m in mines { s.toggleFlag(m) }
        let hint = s.hint()
        #expect(hint?.kind == .safe)
        #expect(hint?.cells == [GridPoint(row: 0, col: 0)])
        #expect(hint?.explanation.hasPrefix("All 3 mines are accounted for") == true)
    }

    /// Following the hints clears every no-guess board without ever hitting a mine.
    @Test(arguments: [M.Level.beginner, .intermediate, .expert])
    func followingHintsClearsTheBoard(level: M.Level) {
        for seed in 1...4 as ClosedRange<UInt64> {
            var s = M.State(level: level, seed: seed)
            var steps = 0
            while s.status != .won, steps < 2000, let hint = s.hint() {
                steps += 1
                switch hint.kind {
                case .start, .safe:
                    for p in hint.cells { s.reveal(p) }
                case .mine:
                    for p in hint.cells { s.toggleFlag(p) }
                case .wrongFlag:
                    for p in hint.cells { s.toggleFlag(p) }
                }
                #expect(s.status != .lost, "\(level) seed \(seed): a hint led onto a mine")
                if s.status == .lost { break }
            }
            #expect(s.status == .won, "\(level) seed \(seed): hints ran out after \(steps) steps")
        }
    }

    @Test func hintIsQuick() {
        var s = M.State(level: .expert, seed: 9)
        s.reveal(GridPoint(row: 15, col: 8))
        let start = threadCPUTime()
        #expect(s.hint() != nil)
        #expect(threadCPUTime() - start < 0.2)
    }
}
