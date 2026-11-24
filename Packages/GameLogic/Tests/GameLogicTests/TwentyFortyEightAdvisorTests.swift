import Foundation
import Testing
@testable import GameLogic

@Suite("2048 hints")
struct TwentyFortyEightAdvisorTests {
    typealias G = TwentyFortyEight

    func state(_ rows: [[Int]]) -> G.State { G.State(grid: rows, seed: 1) }

    /// Whether a swipe changes the board.
    func moves(_ s: G.State, _ d: Direction) -> Bool {
        var copy = s
        return copy.slide(d) != nil
    }

    @Test func noSuggestionWhenNoMoveIsLeft() {
        let s = state([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]])
        #expect(!s.canMove)
        #expect(G.Advisor.bestDirection(for: s) == nil)
    }

    @Test func suggestsOnlyMovesThatDoSomething() {
        let s = state([[2, 4, 2, 4], [4, 2, 4, 2], [8, 16, 8, 0], [16, 8, 16, 2]])
        let legal = Direction.allCases.filter { moves(s, $0) }
        #expect(!legal.contains(.left))
        let hint = G.Advisor.bestDirection(for: s)
        #expect(hint.map(legal.contains) == true)
    }

    @Test func suggestsTheOnlyLegalMove() {
        // Full board; only the bottom-right pair of 2s can merge, and only sideways.
        let s = state([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 8, 16, 16]])
        #expect(Set(Direction.allCases.filter { moves(s, $0) }) == [.left, .right])
        let hint = G.Advisor.bestDirection(for: s)
        #expect(hint == .left || hint == .right)
    }

    @Test func neverSuggestsANoOp() {
        for seed in 1...40 as ClosedRange<UInt64> {
            var s = G.State.newGame(seed: seed)
            for i in 0..<(Int(seed) % 25) {
                let order: [Direction] = [.left, .up, .right, .down]
                guard let d = (0..<4).map({ order[($0 + i) % 4] }).first(where: { moves(s, $0) }) else { break }
                _ = s.move(d)
            }
            guard s.canMove else { continue }
            let hint = G.Advisor.bestDirection(for: s, depth: 2)
            #expect(hint != nil)
            if let hint { #expect(moves(s, hint), "seed \(seed): suggested a swipe that does nothing") }
        }
    }

    @Test func keepsTheBigTileInItsCorner() {
        // Swiping up would drag the 256 out of the corner; right keeps the bottom row in place.
        let s = state([[0, 0, 0, 0], [0, 0, 0, 0], [2, 0, 0, 0], [256, 128, 64, 32]])
        #expect(Set(Direction.allCases.filter { moves(s, $0) }) == [.up, .right])
        #expect(G.Advisor.bestDirection(for: s) == .right)
    }

    @Test func takesAMergeOverJustShuffling() {
        // Two 2s on the bottom row: merging them beats sliding both up.
        let s = state([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [2, 0, 0, 2]])
        let hint = G.Advisor.bestDirection(for: s)
        #expect(hint == .left || hint == .right, "suggested \(String(describing: hint))")
    }

    @Test func emptyCellsScoreBetter() {
        let open = state([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [8, 4, 2, 0]])
        let cluttered = state([[2, 8, 2, 4], [8, 2, 4, 8], [2, 4, 8, 2], [8, 4, 2, 0]])
        #expect(G.Advisor.evaluate(open) > G.Advisor.evaluate(cluttered))
    }

    /// Following the hints plays a decent game: a sign the heuristic and the search work.
    @Test func followingHintsPlaysWell() {
        var s = G.State.newGame(seed: 2048)
        var turns = 0
        while turns < 5000, let d = G.Advisor.bestDirection(for: s, depth: 2) {
            #expect(s.move(d) != nil)
            turns += 1
        }
        #expect(s.highestTile >= 1024, "reached only \(s.highestTile) in \(turns) moves")
    }

    @Test func hintIsQuick() {
        // A crowded board searches deepest.
        let s = state([[2, 4, 8, 16], [4, 8, 16, 32], [0, 2, 0, 64], [0, 0, 4, 128]])
        let start = threadCPUTime()
        _ = G.Advisor.bestDirection(for: s)
        #expect(threadCPUTime() - start < 0.5)
    }
}
