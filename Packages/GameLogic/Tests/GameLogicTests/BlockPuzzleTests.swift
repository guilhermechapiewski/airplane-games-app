import Foundation
import Testing
@testable import GameLogic

@Suite("Block Puzzle")
struct BlockPuzzleTests {
    typealias B = BlockPuzzle

    private func piece(_ rows: [String], id: Int = 100, color: Int = 3) -> B.Piece {
        B.Piece(id: id, rows: rows, color: color)
    }

    // MARK: Catalog

    @Test func catalogCoversAllFamiliesAndOrientations() {
        let families = Set(B.shapes.map(\.family))
        #expect(families == ["dot", "domino", "line3", "corner3", "line4", "square2", "L", "J", "T",
                             "S", "Z", "line5", "corner5", "rect", "square3"])
        func count(_ f: String) -> Int { B.shapes.filter { $0.family == f }.count }
        #expect(count("dot") == 1)
        #expect(count("domino") == 2)
        #expect(count("corner3") == 4)
        #expect(count("square2") == 1)
        #expect(count("L") == 4)
        #expect(count("J") == 4)
        #expect(count("T") == 4)
        #expect(count("S") == 2)
        #expect(count("Z") == 2)
        #expect(count("line5") == 2)
        #expect(count("corner5") == 4)
        #expect(count("rect") == 2)
        #expect(count("square3") == 1)
    }

    @Test func shapesAreNormalizedUniqueAndSized() {
        for shape in B.shapes {
            #expect(shape.cells.map(\.row).min() == 0)
            #expect(shape.cells.map(\.col).min() == 0)
            #expect(Set(shape.cells).count == shape.cells.count)
            #expect((1...9).contains(shape.cells.count))
            #expect(shape.width <= 5 && shape.height <= 5)
            #expect(shape.weight > 0)
            #expect((0..<B.colorCount).contains(shape.color))
        }
        // Orientations of a family are distinct.
        let keys = B.shapes.map { "\($0.family)\($0.cells)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test func parseAndNormalize() {
        let cells = B.parse(["..#", ".##"])
        #expect(cells == [GridPoint(row: 0, col: 1), GridPoint(row: 1, col: 0), GridPoint(row: 1, col: 1)])
        let p = piece(["#..", "###"])
        #expect(p.width == 3 && p.height == 2)
        #expect(p.cells(at: GridPoint(row: 2, col: 3)).first == GridPoint(row: 2, col: 3))
    }

    @Test func originCenteredOnCell() {
        let square = piece(["###", "###", "###"])
        #expect(square.origin(centeredOn: GridPoint(row: 4, col: 4)) == GridPoint(row: 3, col: 3))
        let dot = piece(["#"])
        #expect(dot.origin(centeredOn: GridPoint(row: 2, col: 5)) == GridPoint(row: 2, col: 5))
    }

    // MARK: Placement validation

    @Test func fitsRespectsBoundsAndOccupancy() {
        let board = B.Board(rows: ["#.......", "........"])
        let domino = piece(["##"])
        #expect(!board.fits(domino, at: GridPoint(row: 0, col: 0)))
        #expect(board.fits(domino, at: GridPoint(row: 0, col: 1)))
        #expect(board.fits(domino, at: GridPoint(row: 7, col: 6)))
        #expect(!board.fits(domino, at: GridPoint(row: 7, col: 7)))
        #expect(!board.fits(domino, at: GridPoint(row: -1, col: 3)))
        #expect(board.validOrigins(for: domino).count == 8 * 7 - 1)
    }

    @Test func invalidPlacementChangesNothing() {
        var s = B.State(board: B.Board(rows: ["#......."]), tray: [piece(["##"], id: 1), nil, nil], seed: 1)
        let before = s
        #expect(s.place(slot: 0, at: GridPoint(row: 0, col: 0)) == nil)
        #expect(s.place(slot: 1, at: GridPoint(row: 3, col: 3)) == nil)
        #expect(s.place(slot: 7, at: GridPoint(row: 3, col: 3)) == nil)
        #expect(s == before)
    }

    @Test func placingFillsCellsAndScoresCells() {
        var s = B.State(board: B.Board(), tray: [piece(["##", "#."], id: 1, color: 5), piece(["#"], id: 2), nil], seed: 1)
        let result = s.place(slot: 0, at: GridPoint(row: 2, col: 2))
        #expect(result?.points == 3)
        #expect(result?.lineCount == 0)
        #expect(result?.refilled == false)
        #expect(s.board[GridPoint(row: 2, col: 2)] == 5)
        #expect(s.board[GridPoint(row: 2, col: 3)] == 5)
        #expect(s.board[GridPoint(row: 3, col: 2)] == 5)
        #expect(s.board[GridPoint(row: 3, col: 3)] == nil)
        #expect(s.tray[0] == nil)
        #expect(s.score == 3)
        #expect(s.piecesPlaced == 1)
    }

    // MARK: Clearing

    @Test func clearsRow() {
        let board = B.Board(rows: ["######.."])
        var s = B.State(board: board, tray: [piece(["##"], id: 1), piece(["#"], id: 2), nil], seed: 1)
        let r = s.place(slot: 0, at: GridPoint(row: 0, col: 6))!
        #expect(r.clearedRows == [0])
        #expect(r.clearedColumns.isEmpty)
        #expect(r.clearedCells.count == 8)
        #expect(s.board.isEmpty)
        #expect(s.linesCleared == 1)
    }

    @Test func clearsRowsAndColumnsSimultaneously() {
        // Row 0 and column 0 both complete when the corner dot lands at (0,0).
        var rows = [".#######"]
        for _ in 1..<8 { rows.append("#.......") }
        var s = B.State(board: B.Board(rows: rows), tray: [piece(["#"], id: 1), piece(["#"], id: 2), nil], seed: 1)
        let r = s.place(slot: 0, at: GridPoint(row: 0, col: 0))!
        #expect(r.clearedRows == [0])
        #expect(r.clearedColumns == [0])
        #expect(r.clearedCells.count == 15) // shared corner counted once
        #expect(s.board.isEmpty)
        #expect(r.isPerfectClear)
        #expect(r.points == B.points(cells: 1, lines: 2, streak: 1, perfectClear: true))
    }

    @Test func clearedLinesDoNotRemoveOtherBlocks() {
        let board = B.Board(rows: ["#######.", "#.......", "........"])
        var s = B.State(board: board, tray: [piece(["#"], id: 1), piece(["#"], id: 2), nil], seed: 1)
        let r = s.place(slot: 0, at: GridPoint(row: 0, col: 7))!
        #expect(r.lineCount == 1)
        #expect(!r.isPerfectClear)
        #expect(s.board[GridPoint(row: 1, col: 0)] != nil)
        #expect(s.board.filledCount == 1)
    }

    @Test func linesCompletedPreview() {
        let board = B.Board(rows: ["######..", "######.."])
        let square = piece(["##", "##"])
        let preview = board.linesCompleted(by: square, at: GridPoint(row: 0, col: 6))
        #expect(preview?.rows == [0, 1])
        #expect(preview?.cols == [])
        #expect(board.linesCompleted(by: square, at: GridPoint(row: 0, col: 5)) == nil)
        #expect(board.linesCompleted(by: square, at: GridPoint(row: 4, col: 4))?.rows == [])
    }

    // MARK: Scoring

    @Test func scoringFormula() {
        #expect(B.points(cells: 4, lines: 0, streak: 0) == 4)
        #expect(B.points(cells: 4, lines: 1, streak: 1) == 14)
        #expect(B.points(cells: 4, lines: 2, streak: 1) == 44)
        #expect(B.points(cells: 4, lines: 3, streak: 1) == 94)
        #expect(B.points(cells: 4, lines: 1, streak: 3) == 4 + 10 + 20)
        #expect(B.points(cells: 1, lines: 1, streak: 1, perfectClear: true) == 11 + B.perfectClearBonus)
    }

    @Test func streakGrowsWithConsecutiveClearsAndResets() {
        let board = B.Board(rows: ["#######.", "#######.", "........"])
        let tray: [B.Piece?] = [piece(["#"], id: 1), piece(["#"], id: 2), piece(["#"], id: 3)]
        var s = B.State(board: board, tray: tray, seed: 1)
        let first = s.place(slot: 0, at: GridPoint(row: 0, col: 7))!
        #expect(first.streak == 1)
        let second = s.place(slot: 1, at: GridPoint(row: 1, col: 7))!
        #expect(second.streak == 2)
        #expect(second.points == B.points(cells: 1, lines: 1, streak: 2, perfectClear: true))
        let third = s.place(slot: 2, at: GridPoint(row: 5, col: 5))!
        #expect(third.streak == 0)
        #expect(s.streak == 0)
        #expect(s.score == first.points + second.points + third.points)
    }

    // MARK: Tray

    @Test func newGameDealsThreePieces() {
        let s = B.State.newGame(seed: 42)
        #expect(s.tray.count == 3)
        #expect(s.remainingPieces.count == 3)
        #expect(Set(s.remainingPieces.map(\.id)).count == 3)
        #expect(!s.isOver)
        #expect(s.score == 0)
    }

    @Test func trayRefillsOnlyWhenEmpty() {
        var s = B.State(board: B.Board(), tray: [piece(["#"], id: 1), piece(["#"], id: 2), piece(["#"], id: 3)], seed: 7)
        #expect(s.place(slot: 0, at: GridPoint(row: 0, col: 0))?.refilled == false)
        #expect(s.place(slot: 1, at: GridPoint(row: 0, col: 1))?.refilled == false)
        let last = s.place(slot: 2, at: GridPoint(row: 0, col: 2))
        #expect(last?.refilled == true)
        #expect(s.remainingPieces.count == 3)
        #expect(s.remainingPieces.allSatisfy { $0.id > 3 })
    }

    @Test func refillAlwaysOffersAPlayablePiece() {
        // A nearly-full checkerboard-ish board where only single holes remain.
        var rows: [String] = []
        for r in 0..<8 {
            rows.append(String((0..<8).map { c in (r + c) % 3 == 0 ? "." : "#" }))
        }
        let board = B.Board(rows: rows)
        #expect(board.fullRows.isEmpty && board.fullColumns.isEmpty)
        for seed in UInt64(0)..<200 {
            let s = B.State(board: board, tray: [], seed: seed)
            #expect(s.remainingPieces.contains { board.fitsAnywhere($0) }, "seed \(seed)")
        }
    }

    @Test func dealsAreDeterministicWithSeed() {
        let a = B.State.newGame(seed: 99)
        let b = B.State.newGame(seed: 99)
        #expect(a == b)
        let c = B.State.newGame(seed: 100)
        #expect(a.remainingPieces.map(\.cells) != c.remainingPieces.map(\.cells)
                || a.remainingPieces.map(\.color) != c.remainingPieces.map(\.color)
                || B.State.newGame(seed: 101).remainingPieces.map(\.cells) != a.remainingPieces.map(\.cells))
    }

    @Test func generatorUsesWholeCatalog() {
        var families = Set<String>()
        for seed in UInt64(0)..<400 {
            for p in B.State.newGame(seed: seed).remainingPieces { families.insert(p.family) }
        }
        #expect(families == Set(B.shapes.map(\.family)))
    }

    // MARK: Game over

    @Test func gameOverWhenNothingFits() {
        // Checkerboard of holes: only single cells are free, so a domino cannot fit.
        var rows: [String] = []
        for r in 0..<8 {
            rows.append(String((0..<8).map { c in (r + c) % 2 == 0 ? "." : "#" }))
        }
        let board = B.Board(rows: rows)
        #expect(board.fullRows.isEmpty)
        let s = B.State(board: board, tray: [piece(["##"], id: 1), nil, piece(["#", "#"], id: 2)], seed: 1)
        #expect(s.isOver)
        let alive = B.State(board: board, tray: [piece(["##"], id: 1), piece(["#"], id: 2), nil], seed: 1)
        #expect(!alive.isOver)
        #expect(!alive.canPlaceAnywhere(slot: 0))
        #expect(alive.canPlaceAnywhere(slot: 1))
    }

    @Test func randomPlayoutsStayConsistentAndEnd() {
        for seed in UInt64(1)...30 {
            var s = B.State.newGame(seed: seed)
            var moves = 0
            var rng = SeededRandom(seed: seed &* 31)
            while !s.isOver && moves < 2000 {
                let options = s.tray.indices.flatMap { slot -> [(Int, GridPoint)] in
                    guard let p = s.tray[slot] else { return [] }
                    return s.board.validOrigins(for: p).map { (slot, $0) }
                }
                #expect(!options.isEmpty)
                let (slot, origin) = options.randomElement(using: &rng)!
                let before = s.score
                let r = s.place(slot: slot, at: origin)!
                #expect(s.score == before + r.points)
                #expect(s.board.fullRows.isEmpty && s.board.fullColumns.isEmpty)
                moves += 1
            }
            #expect(s.isOver)
        }
    }

    // MARK: Snapping

    @Test func nearestValidOriginSnaps() {
        let board = B.Board(rows: ["........", "...#...."])
        let square = piece(["##", "##"])
        #expect(board.nearestValidOrigin(for: square, row: 4.2, col: 4.4) == GridPoint(row: 4, col: 4))
        // (0,3) overlaps the block at (1,3); nearest valid is (0,4) or (0,1)/(2,3)...
        let snapped = board.nearestValidOrigin(for: square, row: 0.1, col: 3.4)
        #expect(snapped == GridPoint(row: 0, col: 4))
        // Far outside the board yields nothing.
        #expect(board.nearestValidOrigin(for: square, row: -5, col: 3) == nil)
        // Slightly outside is clamped onto the board.
        #expect(board.nearestValidOrigin(for: square, row: -0.4, col: 6.6) == GridPoint(row: 0, col: 6))
    }

    // MARK: Persistence

    @Test func codableRoundTrip() throws {
        var s = B.State.newGame(seed: 5)
        if let p = s.tray[0], let o = s.board.validOrigins(for: p).first { s.place(slot: 0, at: o) }
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(B.State.self, from: data)
        #expect(decoded == s)
        // The RNG survives the round-trip, so future deals match.
        var a = s, b = decoded
        for slot in 0..<3 {
            if let p = a.tray[slot], let o = a.board.validOrigins(for: p).first {
                a.place(slot: slot, at: o)
                b.place(slot: slot, at: o)
            }
        }
        #expect(a == b)
    }
}
