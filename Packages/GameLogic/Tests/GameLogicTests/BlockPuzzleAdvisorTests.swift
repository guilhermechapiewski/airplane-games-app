import Foundation
import Testing
@testable import GameLogic

@Suite("Block Puzzle hints")
struct BlockPuzzleAdvisorTests {
    typealias B = BlockPuzzle

    func piece(_ id: Int, _ rows: [String]) -> B.Piece { B.Piece(id: id, rows: rows) }

    @Test func noSuggestionWhenNothingFits() {
        // Every row and column has exactly one empty cell, none of them adjacent: a 2×2 fits nowhere.
        let board = B.Board(rows: [
            "#######.", "######.#", "#####.##", "####.###",
            "###.####", "##.#####", "#.######", ".#######",
        ])
        let s = B.State(board: board, tray: [piece(0, ["##", "##"]), nil, nil], seed: 1)
        #expect(s.isOver)
        #expect(B.Advisor.suggestion(for: s) == nil)
    }

    @Test func completesALine() {
        let board = B.Board(rows: [
            "######..", "........", "........", "........",
            "........", "........", "........", "........",
        ])
        let s = B.State(board: board, tray: [piece(0, ["##"]), nil, nil], seed: 1)
        let hint = B.Advisor.suggestion(for: s)
        #expect(hint == .init(slot: 0, origin: GridPoint(row: 0, col: 6), lines: 1))
    }

    @Test func prefersTheBiggerClear() {
        // The 3-bar finishes one row on top, or three columns at the bottom-left.
        let board = B.Board(rows: [
            "#####...", "###.....", "###.....", "###.....",
            "###.....", "###.....", "###.....", "...#####",
        ])
        let s = B.State(board: board, tray: [piece(0, ["###"]), nil, nil], seed: 1)
        let hint = B.Advisor.suggestion(for: s)
        #expect(hint?.origin == GridPoint(row: 7, col: 0))
        #expect(hint?.lines == 4)
    }

    @Test func keepsRoomForTheRestOfTheTray() {
        // Only one 3×3 space; the single blocks must go into the diagonal holes, not into it.
        let board = B.Board(rows: [
            "...#####", "...#####", "...#####", "###.####",
            "####.###", "#####.##", "######.#", "#######.",
        ])
        var s = B.State(board: board, tray: [piece(0, ["#"]), piece(1, ["###", "###", "###"]), piece(2, ["#"])], seed: 1)
        let first = B.Advisor.suggestion(for: s)
        #expect(first != nil)
        if let first, first.slot != 1 {
            #expect(!(0...2).contains(first.origin.row) || !(0...2).contains(first.origin.col),
                    "a single block went into the only space for the square")
        }
        // Following the hints places all three pieces.
        for _ in 0..<3 {
            guard let hint = B.Advisor.suggestion(for: s) else { break }
            #expect(s.place(slot: hint.slot, at: hint.origin) != nil)
            if s.tray.allSatisfy({ $0 == nil }) || s.piecesPlaced == 3 { break }
        }
        #expect(s.piecesPlaced == 3)
    }

    @Test func avoidsLeavingHoles() {
        let open = B.Board(rows: [
            "........", "........", "........", "........",
            "........", "........", "##......", "###.....",
        ])
        let holey = B.Board(rows: [
            "........", "........", "........", "........",
            "........", "........", "#.#.#...", ".#.#....",
        ])
        #expect(B.Advisor.quality(open) > B.Advisor.quality(holey))
    }

    @Test func suggestionsAreAlwaysLegal() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var s = B.State.newGame(seed: seed)
            for _ in 0..<15 {
                guard !s.isOver, let hint = B.Advisor.suggestion(for: s) else { break }
                #expect(s.canPlace(slot: hint.slot, at: hint.origin))
                s.place(slot: hint.slot, at: hint.origin)
            }
        }
    }

    /// Following the hints keeps a game going much longer than dropping pieces anywhere.
    @Test func followingHintsPlaysWell() {
        func play(seed: UInt64, hinted: Bool) -> Int {
            var s = B.State.newGame(seed: seed)
            while !s.isOver, s.piecesPlaced < 200 {
                if hinted, let hint = B.Advisor.suggestion(for: s) {
                    s.place(slot: hint.slot, at: hint.origin)
                } else if let slot = s.tray.indices.first(where: { s.canPlaceAnywhere(slot: $0) }),
                          let origin = s.board.validOrigins(for: s.tray[slot]!).first {
                    s.place(slot: slot, at: origin)
                } else {
                    break
                }
            }
            return s.piecesPlaced
        }
        let seeds: [UInt64] = [3, 14, 15]
        let hinted = seeds.map { play(seed: $0, hinted: true) }.reduce(0, +)
        let naive = seeds.map { play(seed: $0, hinted: false) }.reduce(0, +)
        #expect(hinted > naive * 2, "hinted \(hinted) vs naive \(naive)")
    }

    @Test func hintIsQuick() {
        // An empty board with three single blocks has the most placements to try.
        let s = B.State(board: B.Board(), tray: [piece(0, ["#"]), piece(1, ["#"]), piece(2, ["#"])], seed: 1)
        let start = threadCPUTime()
        #expect(B.Advisor.suggestion(for: s) != nil)
        #expect(threadCPUTime() - start < 1)
    }
}
