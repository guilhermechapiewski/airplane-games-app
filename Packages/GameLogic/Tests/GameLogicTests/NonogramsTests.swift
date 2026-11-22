import Foundation
import Testing
@testable import GameLogic

@Suite("Nonograms")
struct NonogramsTests {
    typealias N = Nonograms
    typealias S = Nonograms.Solver

    func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }

    func line(_ s: String) -> [S.Cell] {
        s.map { $0 == "#" ? .filled : $0 == "x" ? .empty : .unknown }
    }

    func text(_ cells: [S.Cell]) -> String {
        String(cells.map { $0 == .filled ? "#" : $0 == .empty ? "x" : "?" })
    }

    static let heart = N.Puzzle(id: "t-heart", title: "Heart", color: 0, art: [
        ".#.#.",
        "#####",
        "#####",
        ".###.",
        "..#..",
    ])

    // MARK: Clues

    @Test func clueComputation() {
        #expect(N.clue(for: []) == [])
        #expect(N.clue(for: [false, false]) == [])
        #expect(N.clue(for: [true, true, true]) == [3])
        #expect(N.clue(for: [true, false, true, true, false, false, true]) == [1, 2, 1])
        #expect(N.clue(for: [false, true, true, false]) == [2])
    }

    @Test func puzzleCluesFromArt() {
        let h = Self.heart
        #expect(h.width == 5 && h.height == 5)
        #expect(h.rowClues == [[1, 1], [5], [5], [3], [1]])
        #expect(h.columnClues == [[2], [4], [4], [4], [2]])
        #expect(h[0, 1] && !h[0, 0])
        #expect(h.size == .easy)
        #expect(h.filledCount == 16)
    }

    // MARK: Line solver

    @Test func lineSolverOverlap() {
        // A block of 4 in 5 cells must cover the middle 3.
        #expect(text(S.solveLine(clue: [4], line: line("?????"))!) == "?###?")
        #expect(text(S.solveLine(clue: [5], line: line("?????"))!) == "#####")
        #expect(text(S.solveLine(clue: [], line: line("?????"))!) == "xxxxx")
        #expect(text(S.solveLine(clue: [2, 2], line: line("?????"))!) == "##x##")
        #expect(text(S.solveLine(clue: [1], line: line("?????"))!) == "?????")
    }

    @Test func lineSolverUsesKnownCells() {
        #expect(text(S.solveLine(clue: [1], line: line("??#??"))!) == "xx#xx")
        #expect(text(S.solveLine(clue: [2], line: line("x?#??"))!) == "x?#?x")
        #expect(text(S.solveLine(clue: [3], line: line("??x?????"))!) == "xxx??#??")
        #expect(text(S.solveLine(clue: [1, 3], line: line("#????????"))!) == "#x???????")
    }

    @Test func lineSolverDetectsContradictions() {
        #expect(S.solveLine(clue: [3], line: line("#x#??")) == nil)
        #expect(S.solveLine(clue: [6], line: line("?????")) == nil)
        #expect(S.solveLine(clue: [], line: line("??#")) == nil)
    }

    @Test func solverSolvesUniquePuzzle() {
        let result = S.solve(Self.heart)
        guard case .solved(let grid) = result else {
            Issue.record("expected solved, got \(result)")
            return
        }
        #expect(grid.flatMap { $0 } == Self.heart.solution)
        #expect(S.isLineSolvable(Self.heart))
    }

    @Test func solverGetsStuckOnAmbiguousPuzzle() {
        // A diagonal pair has two solutions: line logic can't decide.
        let ambiguous = N.Puzzle(id: "t-x", title: "X", rows: [[true, false], [false, true]])
        #expect(S.solve(ambiguous) == .stuck(known: 0))
        #expect(!S.isLineSolvable(ambiguous))
    }

    @Test func solverDetectsContradiction() {
        #expect(S.solve(rowClues: [[2], []], columnClues: [[1], []]) == .contradiction)
    }

    // MARK: Library

    @Test func libraryHasExpectedShape() {
        #expect(N.puzzles(of: .easy).count == 16)
        #expect(N.puzzles(of: .medium).count == 16)
        #expect(N.puzzles(of: .hard).count == 12)
        #expect(N.library.count == 44)
        #expect(Set(N.library.map(\.id)).count == N.library.count, "ids must be unique")
        #expect(Set(N.library.map(\.title)).count >= 40, "titles should be distinct")
        for puzzle in N.library {
            #expect(puzzle.size != nil, "\(puzzle.id) must be a supported square size")
            #expect(!puzzle.title.isEmpty)
            #expect(puzzle.filledCount > puzzle.solution.count / 5, "\(puzzle.id) is too sparse")
            #expect(N.puzzle(id: puzzle.id) == puzzle)
        }
    }

    @Test(arguments: Nonograms.library)
    func everyBundledPuzzleIsLineSolvable(puzzle: Nonograms.Puzzle) {
        #expect(S.isLineSolvable(puzzle), "\(puzzle.title) needs guessing — edit its art")
    }

    // MARK: Board & strokes

    @Test func fillStrokePaintsALockedLine() {
        var b = N.Board(for: Self.heart)
        let stroke = N.Stroke(tool: .fill, start: p(1, 0), startingMark: .empty)
        // Moving mostly right locks to the row even if the finger drifts down a little.
        let changed = b.apply(stroke, to: p(2, 4))
        #expect(changed == [p(1, 0), p(1, 1), p(1, 2), p(1, 3), p(1, 4)])
        #expect(b.isRowSatisfied(1, in: Self.heart))
        #expect(!b.isRowSatisfied(2, in: Self.heart))
    }

    @Test func strokeCellsLockToDominantAxis() {
        let s = N.Stroke(tool: .fill, start: p(2, 2), startingMark: .empty)
        #expect(s.cells(to: p(2, 2)) == [p(2, 2)])
        #expect(s.cells(to: p(0, 3)) == [p(2, 2), p(1, 2), p(0, 2)])
        #expect(s.cells(to: p(3, 0)) == [p(2, 2), p(2, 1), p(2, 0)])
    }

    @Test func strokeStartingOnSameMarkErases() {
        var b = N.Board(for: Self.heart)
        b.apply(N.Stroke(tool: .fill, start: p(0, 0), startingMark: .empty), to: p(0, 4))
        b.apply(N.Stroke(tool: .cross, start: p(1, 0), startingMark: .empty), to: p(1, 4))
        let erase = N.Stroke(tool: .fill, start: p(0, 1), startingMark: b[p(0, 1)])
        #expect(erase.action == .erase(.filled))
        b.apply(erase, to: p(0, 3))
        #expect((0..<5).map { b[0, $0] } == [.filled, .empty, .empty, .empty, .filled])
    }

    @Test func paintingSkipsOtherMarksButOverwriteReplacesThem() {
        var b = N.Board(for: Self.heart)
        b.apply(N.Stroke(tool: .cross, start: p(0, 2), startingMark: .empty), to: p(0, 2))
        // Painting from an empty cell leaves the cross alone.
        b.apply(N.Stroke(tool: .fill, start: p(0, 0), startingMark: .empty), to: p(0, 4))
        #expect(b[0, 2] == .crossed)
        #expect(b[0, 3] == .filled)
        // Starting on a cross with the fill tool converts crosses (and blanks) to fills.
        b.apply(N.Stroke(tool: .fill, start: p(0, 2), startingMark: b[p(0, 2)]), to: p(0, 2))
        #expect(b[0, 2] == .filled)
    }

    @Test func completionIgnoresCrossesAndDetectsMistakes() {
        var b = N.Board(for: Self.heart)
        #expect(!b.isSolved(Self.heart))
        #expect(b.isBlank)
        for point in b.allPoints where Self.heart[point] {
            b.apply(N.Stroke(tool: .fill, start: point, startingMark: .empty), to: point)
        }
        #expect(b.isSolved(Self.heart))
        #expect(b.mistakes(in: Self.heart).isEmpty)
        // Crosses on blank cells don't matter...
        b.apply(N.Stroke(tool: .cross, start: p(0, 0), startingMark: .empty), to: p(0, 0))
        #expect(b.isSolved(Self.heart))
        // ...but an extra fill breaks the solution and is a mistake.
        b.apply(N.Stroke(tool: .fill, start: p(4, 0), startingMark: .empty), to: p(4, 0))
        #expect(!b.isSolved(Self.heart))
        #expect(b.mistakes(in: Self.heart) == [p(4, 0)])
        #expect(N.Board.solved(Self.heart).isSolved(Self.heart))
    }

    @Test func crossOnPictureCellIsAMistake() {
        var b = N.Board(for: Self.heart)
        b.apply(N.Stroke(tool: .cross, start: p(2, 2), startingMark: .empty), to: p(2, 2))
        #expect(b.mistakes(in: Self.heart) == [p(2, 2)])
    }

    @Test func hintFixesMistakesFirst() {
        var b = N.Board(for: Self.heart)
        b.apply(N.Stroke(tool: .fill, start: p(0, 0), startingMark: .empty), to: p(0, 0))
        let hint = b.hint(for: Self.heart)
        #expect(hint?.point == p(0, 0))
        #expect(hint?.mark == .crossed)
    }

    @Test func hintRevealsADeducibleCell() {
        let b = N.Board(for: Self.heart)
        let hint = b.hint(for: Self.heart)
        #expect(hint != nil)
        if let hint {
            // Rows 1-2 are full lines, so the first deducible picture cell is in row 1.
            #expect(hint.point.row == 1)
            #expect(hint.mark == .filled)
            #expect(Self.heart[hint.point])
        }
    }

    @Test func repeatedHintsSolveEveryPuzzle() {
        for puzzle in N.library {
            var b = N.Board(for: puzzle)
            var steps = 0
            while !b.isSolved(puzzle), let hint = b.hint(for: puzzle), steps < puzzle.solution.count * 2 {
                b[hint.point] = hint.mark
                steps += 1
            }
            #expect(b.isSolved(puzzle), "\(puzzle.title)")
            #expect(b.mistakes(in: puzzle).isEmpty)
        }
    }

    @Test func boardCodableRoundTrip() throws {
        var b = N.Board(for: Self.heart)
        b.apply(N.Stroke(tool: .fill, start: p(1, 0), startingMark: .empty), to: p(1, 4))
        b.apply(N.Stroke(tool: .cross, start: p(0, 0), startingMark: .empty), to: p(0, 0))
        let data = try JSONEncoder().encode(b)
        #expect(try JSONDecoder().decode(N.Board.self, from: data) == b)

        let stroke = N.Stroke(tool: .cross, start: p(3, 3), startingMark: .filled)
        let decoded = try JSONDecoder().decode(N.Stroke.self, from: JSONEncoder().encode(stroke))
        #expect(decoded == stroke)
    }

    @Test func sizesMatchDimensions() {
        #expect(N.Size(dimension: 5) == .easy)
        #expect(N.Size(dimension: 10) == .medium)
        #expect(N.Size(dimension: 15) == .hard)
        #expect(N.Size(dimension: 7) == nil)
    }
}
