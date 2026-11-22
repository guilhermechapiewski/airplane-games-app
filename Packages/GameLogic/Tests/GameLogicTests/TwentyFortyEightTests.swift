import Foundation
import Testing
@testable import GameLogic

@Suite("2048")
struct TwentyFortyEightTests {
    typealias G = TwentyFortyEight

    /// Builds a state from a row-major grid where 0 = empty.
    func state(_ rows: [[Int]]) -> G.State {
        G.State(grid: rows, seed: 1)
    }

    @Test func newGameHasTwoTiles() {
        let s = G.State.newGame(size: 4, seed: 123)
        #expect(s.tiles.count == 2)
        #expect(s.tiles.allSatisfy { $0.value == 2 || $0.value == 4 })
        #expect(s.score == 0)
    }

    @Test func slideLeftCompactsTiles() {
        var s = state([[0, 2, 0, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let outcome = s.slide(.left)
        #expect(outcome != nil)
        #expect(s.valueGrid[0] == [2, 4, 0, 0])
    }

    @Test func mergeOncePerMove() {
        var s = state([[2, 2, 2, 2], [4, 4, 8, 0], [2, 2, 4, 0], [0, 0, 0, 0]])
        let outcome = s.slide(.left)
        #expect(s.valueGrid[0] == [4, 4, 0, 0])
        #expect(s.valueGrid[1] == [8, 8, 0, 0])
        #expect(s.valueGrid[2] == [4, 4, 0, 0])
        #expect(outcome?.scoreGained == 4 + 4 + 8 + 4)
        #expect(s.score == 20)
    }

    @Test func mergePrefersTilesNearestTheWall() {
        var s = state([[2, 2, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        _ = s.slide(.right)
        #expect(s.valueGrid[0] == [0, 0, 2, 4])
    }

    @Test func slideUpAndDown() {
        var s = state([[2, 0, 0, 0], [2, 0, 0, 0], [4, 0, 0, 0], [4, 0, 0, 0]])
        _ = s.slide(.up)
        #expect(s.valueGrid.map { $0[0] } == [4, 8, 0, 0])
        var d = state([[2, 0, 0, 0], [0, 0, 0, 0], [2, 0, 0, 0], [8, 0, 0, 0]])
        _ = d.slide(.down)
        #expect(d.valueGrid.map { $0[0] } == [0, 0, 4, 8])
    }

    @Test func noOpMoveReturnsNilAndDoesNotChangeState() {
        var s = state([[2, 4, 8, 16], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let before = s
        #expect(s.slide(.left) == nil)
        #expect(s == before)
    }

    @Test func consumedTilesReportTheirDestination() {
        var s = state([[0, 0, 2, 2], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let outcome = s.slide(.left)!
        #expect(outcome.consumed.count == 1)
        #expect(outcome.consumed[0].position == GridPoint(row: 0, col: 0))
        #expect(outcome.merged.count == 1)
        let merged = s.tiles.first { outcome.merged.contains($0.id) }!
        #expect(merged.value == 4)
        #expect(merged.position == GridPoint(row: 0, col: 0))
    }

    @Test func moveSpawnsExactlyOneTile() {
        var s = state([[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let outcome = s.move(.right)
        #expect(outcome != nil)
        #expect(s.tiles.count == 2)
        #expect(outcome?.spawned != nil)
    }

    @Test func gameOverDetection() {
        let stuck = state([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]])
        #expect(!stuck.canMove)
        let mergeable = state([[2, 2, 4, 8], [4, 8, 16, 32], [8, 16, 32, 64], [16, 32, 64, 128]])
        #expect(mergeable.canMove)
    }

    @Test func reachingTargetSetsWon() {
        var s = state([[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        #expect(!s.hasWon)
        _ = s.move(.left)
        #expect(s.hasWon)
        #expect(s.highestTile == 2048)
    }

    @Test func tileIdsStayUnique() {
        var s = G.State.newGame(size: 4, seed: 99)
        let dirs: [Direction] = [.left, .up, .right, .down]
        for i in 0..<300 {
            _ = s.move(dirs[i % 4])
            #expect(Set(s.tiles.map(\.id)).count == s.tiles.count)
            #expect(Set(s.tiles.map(\.position)).count == s.tiles.count)
        }
    }

    @Test func deterministicWithSeed() {
        var a = G.State.newGame(size: 4, seed: 5)
        var b = G.State.newGame(size: 4, seed: 5)
        for d in [Direction.left, .up, .right, .down, .left] {
            _ = a.move(d); _ = b.move(d)
        }
        #expect(a == b)
    }

    @Test func codableRoundTrip() throws {
        var s = G.State.newGame(size: 4, seed: 8)
        _ = s.move(.left)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(G.State.self, from: data) == s)
    }
}
