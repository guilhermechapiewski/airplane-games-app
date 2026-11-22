import Foundation
import Testing
@testable import GameLogic

@Suite("Sudoku")
struct SudokuTests {
    typealias S = Sudoku

    /// Parses 81 characters where `.` or `0` means empty.
    static func grid(_ text: String) -> [Int] {
        text.compactMap { ch -> Int? in
            if ch == "." { return 0 }
            return ch.wholeNumberValue
        }
    }

    // A classic puzzle with a known unique solution.
    static let puzzle = grid("""
        53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79
        """)
    static let solution = grid("""
        534678912672195348198342567859761423426853791713924856961537284287419635345286179
        """)

    // MARK: Geometry

    @Test func geometry() {
        #expect(S.rows.count == 9 && S.columns.count == 9 && S.boxes.count == 9)
        #expect(S.boxes[4] == [30, 31, 32, 39, 40, 41, 48, 49, 50])
        #expect(S.peers.allSatisfy { $0.count == 20 })
        #expect(S.box(of: 80) == 8 && S.box(of: 0) == 0 && S.box(of: 33) == 5)
        #expect(S.Unit.column(2).cells == [2, 11, 20, 29, 38, 47, 56, 65, 74])
        #expect(Set(S.units(of: 40)) == [.row(4), .column(4), .box(4)])
        #expect(S.digits(in: S.allDigits) == Array(1...9))
    }

    // MARK: Solver

    @Test func solvesKnownPuzzle() {
        #expect(S.solve(Self.puzzle) == Self.solution)
        #expect(S.countSolutions(Self.puzzle) == 1)
        #expect(S.isSolved(Self.solution))
    }

    @Test func detectsMultipleAndNoSolutions() {
        #expect(S.countSolutions([Int](repeating: 0, count: 81), limit: 2) == 2)
        var conflicting = Self.puzzle
        conflicting[2] = 5 // duplicate 5 in row 0
        #expect(S.countSolutions(conflicting) == 0)
        #expect(S.solve(conflicting) == nil)
        // Only the first row given: many solutions, counting stops at the limit.
        var loose = [Int](repeating: 0, count: 81)
        for i in 0..<9 { loose[i] = Self.solution[i] }
        #expect(S.countSolutions(loose, limit: 2) == 2)
        #expect(S.countSolutions(loose, limit: 5) == 5)
        // Unsolvable without direct conflicts: cell 0 has no candidates.
        var dead = [Int](repeating: 0, count: 81)
        for (i, d) in [1, 2, 3, 4, 5, 6, 7, 8].enumerated() { dead[i + 1] = d }
        dead[9] = 9
        #expect(S.countSolutions(dead) == 0)
        #expect(S.countSolutions([1, 2, 3]) == 0)
    }

    @Test func solvesHardestKnownPuzzle() {
        // "AI Escargot"-style hard puzzle: still solved quickly by backtracking.
        let hard = Self.grid("1....7.9..3..2...8..96..5....53..9...1..8...26....4...3......1..4......7..7...3..")
        let solved = S.solve(hard)
        #expect(solved != nil)
        if let solved {
            #expect(S.isSolved(solved))
            for i in 0..<81 where hard[i] != 0 { #expect(solved[i] == hard[i]) }
        }
    }

    // MARK: Conflicts

    @Test func conflictDetection() {
        var g = Self.puzzle
        #expect(S.conflicts(in: g).isEmpty)
        g[2] = 3 // row 0 already has 3 at index 1
        #expect(S.conflicts(in: g) == [1, 2])
        g[2] = 9 // box 0 already has 9 at index 19
        #expect(S.conflicts(in: g) == [2, 19])
        g[2] = 4
        #expect(S.conflicts(in: g).isEmpty)
        #expect(!S.isSolved(g))
    }

    // MARK: Logical grading

    @Test func gradesKnownPuzzle() {
        let grade = S.grade(Self.puzzle)
        #expect(grade.solved)
        #expect(grade.level <= 2)
    }

    @Test func gradeOfSolvedGridIsTrivial() {
        let grade = S.grade(Self.solution)
        #expect(grade.solved && grade.hardest == nil && grade.level == 0)
    }

    @Test func singlesSolveClassicPuzzle() {
        var solver = LogicSolver(Self.puzzle)!
        // Use singles only until none remain, then make sure each step is sound.
        while let step = solver.nextStep(maxLevel: 2) {
            if let (cell, digit) = step.placement { #expect(Self.solution[cell] == digit) }
            solver.apply(step)
        }
        #expect(solver.values == Self.solution)
    }

    @Test func techniqueLevelsAreOrdered() {
        #expect(S.Technique.nakedSingle < S.Technique.hiddenSingle)
        #expect(S.Technique.allCases.map(\.level) == S.Technique.allCases.map(\.level).sorted())
        #expect(S.Technique.allCases.allSatisfy { !$0.title.isEmpty })
    }

    // MARK: Generator

    @Test(arguments: Difficulty.allCases)
    func generatesUniqueGradedPuzzles(_ difficulty: Difficulty) {
        var clueCounts: [Int] = []
        // Expert generation is the slow one in debug builds; fewer seeds keep the suite quick.
        for seed in 0..<(difficulty == .expert ? 16 : 40) {
            let p = S.generate(difficulty: difficulty, seed: UInt64(seed) &* 0x9E37_79B9 &+ 17)
            #expect(p.difficulty == difficulty)
            #expect(S.isSolved(p.solution))
            #expect(S.countSolutions(p.givens, limit: 2) == 1, "seed \(seed) not unique")
            #expect(S.solve(p.givens) == p.solution)
            for i in 0..<81 where p.givens[i] != 0 { #expect(p.givens[i] == p.solution[i]) }
            let grade = S.grade(p.givens)
            #expect(grade.solved, "seed \(seed) needs techniques beyond the grader")
            #expect(grade.difficulty == difficulty, "seed \(seed) graded \(grade.difficulty)")
            #expect(p.hardestTechnique == grade.hardest)
            expectSoundDeductions(p)
            // Symmetric under 180° rotation.
            for i in 0..<81 { #expect((p.givens[i] == 0) == (p.givens[80 - i] == 0)) }
            clueCounts.append(p.clueCount)
        }
        let range: ClosedRange<Int> = switch difficulty {
        case .easy: 36...44
        case .medium: 30...34
        case .hard: 25...30
        case .expert: 22...28
        }
        #expect(clueCounts.allSatisfy(range.contains), "\(clueCounts)")
    }

    /// Every step of the logical solver is consistent with the known solution.
    func expectSoundDeductions(_ p: S.Puzzle) {
        var solver = LogicSolver(p.givens)!
        while let step = solver.nextStep(maxLevel: 4) {
            if let (cell, digit) = step.placement { #expect(p.solution[cell] == digit) }
            for (cell, mask) in step.eliminations {
                #expect(mask & S.bit(p.solution[cell]) == 0, "\(step.technique) removed the answer")
            }
            solver.apply(step)
        }
        #expect(solver.values == p.solution)
    }

    @Test func generationIsDeterministic() {
        for d in Difficulty.allCases {
            let a = S.generate(difficulty: d, seed: 42)
            #expect(a == S.generate(difficulty: d, seed: 42))
            #expect(a.givens != S.generate(difficulty: d, seed: 43).givens)
        }
    }

    @Test func expertGenerationIsFast() {
        // Measure this thread's CPU time, not wall time, so suites running in
        // parallel (competing for cores) can't make the check flaky.
        func threadCPUTime() -> Double {
            var ts = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
            return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
        }
        let start = threadCPUTime()
        for seed in 0..<6 { _ = S.generate(difficulty: .expert, seed: UInt64(seed) + 1000) }
        // Release builds take ~20 ms per expert puzzle; the bound is generous for
        // unoptimized test builds.
        #expect((threadCPUTime() - start) / 6 < 4)
    }

    // MARK: Game

    func newGame() -> S.Game {
        S.Game(puzzle: S.Puzzle(givens: Self.puzzle, solution: Self.solution, difficulty: .easy))
    }

    @Test func givensAreLocked() {
        var g = newGame()
        #expect(g.isGiven(0))
        let ok1 = g.enter(1, at: 0) == nil
        #expect(ok1)
        let ok2 = !g.toggleNote(1, at: 0)
        #expect(ok2)
        let ok3 = !g.erase(at: 0)
        #expect(ok3)
        #expect(!g.canUndo)
    }

    @Test func enterAndEraseDigit() {
        var g = newGame()
        let outcome = g.enter(4, at: 2)
        #expect(outcome != nil && outcome?.conflicts == false)
        #expect(g.values[2] == 4)
        #expect(g.remaining(4) == 9 - g.values.filter { $0 == 4 }.count)
        let ok4 = g.enter(4, at: 2) == nil // same digit: no change
        #expect(ok4)
        let ok5 = g.erase(at: 2)
        #expect(ok5)
        #expect(g.values[2] == 0)
        let ok6 = !g.erase(at: 2)
        #expect(ok6)
        let ok7 = g.enter(0, at: 2) == nil && g.enter(10, at: 2) == nil && g.enter(1, at: 81) == nil
        #expect(ok7)
    }

    @Test func conflictingEntryIsReported() {
        var g = newGame()
        let outcome = g.enter(5, at: 2) // 5 already at index 0
        #expect(outcome?.conflicts == true)
        #expect(g.conflicts == [0, 2])
        #expect(g.isWrong(2))
    }

    @Test func notesToggleAndClearOnPlacement() {
        var g = newGame()
        let ok8 = g.toggleNote(4, at: 2)
        #expect(ok8)
        let ok9 = g.toggleNote(1, at: 2)
        #expect(ok9)
        let ok10 = g.toggleNote(4, at: 3) // same row
        #expect(ok10)
        let ok11 = g.toggleNote(4, at: 10) // same box
        #expect(ok11)
        let ok12 = g.toggleNote(4, at: 47) // same column (row 5, col 2)
        #expect(ok12)
        let ok13 = g.toggleNote(4, at: 72) // unrelated
        #expect(ok13)
        #expect(g.notes(at: 2) == [1, 4])
        let ok14 = g.toggleNote(1, at: 2)
        #expect(ok14)
        #expect(g.notes(at: 2) == [4])

        g.enter(4, at: 2)
        #expect(g.notes[2] == 0)
        #expect(g.notes[3] == 0 && g.notes[10] == 0 && g.notes[47] == 0)
        #expect(g.notes(at: 72) == [4])
        // Notes can't be added to a filled cell.
        let ok15 = !g.toggleNote(5, at: 2)
        #expect(ok15)

        // Undo restores the digit removal and every cleared note in one step.
        g.undo()
        #expect(g.values[2] == 0)
        #expect(g.notes(at: 2) == [4])
        #expect(g.notes(at: 3) == [4] && g.notes(at: 10) == [4] && g.notes(at: 47) == [4])
    }

    @Test func eraseClearsNotesWhenEmpty() {
        var g = newGame()
        g.toggleNote(1, at: 2)
        g.toggleNote(2, at: 2)
        let ok16 = g.erase(at: 2)
        #expect(ok16)
        #expect(g.notes[2] == 0)
        g.undo()
        #expect(g.notes(at: 2) == [1, 2])
    }

    @Test func fullUndoHistory() {
        var g = newGame()
        let empties = (0..<81).filter { Self.puzzle[$0] == 0 }
        for cell in empties { g.enter(Self.solution[cell], at: cell) }
        #expect(g.isSolved)
        #expect(g.undoCount == empties.count)
        while g.canUndo { g.undo() }
        #expect(g.values == Self.puzzle)
        let ok17 = g.undo().isEmpty
        #expect(ok17)
    }

    @Test func completedUnitsAndSolve() {
        var g = newGame()
        // Fill row 0 except its last empty cell.
        let rowEmpties = S.rows[0].filter { Self.puzzle[$0] == 0 }
        for cell in rowEmpties.dropLast() {
            let ok18 = g.enter(Self.solution[cell], at: cell)?.completedUnits.contains(.row(0)) == false
            #expect(ok18)
        }
        let last = rowEmpties.last!
        let ok19 = g.enter(Self.solution[last], at: last)?.completedUnits.contains(.row(0)) == true
        #expect(ok19)

        var outcome: S.Outcome?
        for cell in 0..<81 where g.values[cell] == 0 { outcome = g.enter(Self.solution[cell], at: cell) }
        #expect(outcome?.solved == true)
        #expect(outcome?.completedUnits.count == 3)
    }

    @Test func wrongFullGridIsNotSolved() {
        var g = newGame()
        for cell in 0..<81 where g.values[cell] == 0 { g.enter(Self.solution[cell], at: cell) }
        // Swap two player digits in the same row to break it.
        let editable = S.rows[0].filter { Self.puzzle[$0] == 0 }
        let a = editable[0], b = editable[1]
        let da = g.values[a], db = g.values[b]
        #expect(da != db)
        g.enter(db, at: a)
        #expect(!g.isSolved)
        #expect(g.conflicts.contains(a) && g.conflicts.contains(b))
    }

    @Test func hintsFillCorrectLogicalCells() {
        for d in Difficulty.allCases {
            var g = S.Game(puzzle: S.generate(difficulty: d, seed: 7))
            var count = 0
            while !g.isSolved, let hint = g.applyHint()?.hint {
                #expect(g.values[hint.cell] == g.puzzle.solution[hint.cell])
                #expect(hint.technique != nil, "\(d): logical solver got stuck")
                count += 1
            }
            #expect(g.isSolved)
            #expect(g.hintsUsed == count)
            #expect(g.hinted.count == count)
            #expect(g.nextHint() == nil)
        }
    }

    @Test func hintPrefersEasiestTechnique() {
        let g = newGame()
        let hint = g.nextHint()
        #expect(hint?.technique == .nakedSingle)
        if let hint { #expect(Self.solution[hint.cell] == hint.digit) }
    }

    @Test func hintFixesAroundWrongDigits() {
        var g = newGame()
        // Put a wrong digit in every empty cell of row 0.
        for cell in S.rows[0] where g.values[cell] == 0 {
            g.enter(Self.solution[cell] % 9 + 1, at: cell)
        }
        var guardCount = 0
        while !g.isSolved, guardCount < 81 {
            let ok20 = g.applyHint() != nil
            #expect(ok20)
            guardCount += 1
        }
        #expect(g.isSolved)
    }

    @Test func undoOfHintKeepsCount() {
        var g = newGame()
        let result = g.applyHint()
        #expect(result != nil)
        g.undo()
        #expect(g.hintsUsed == 1)
        #expect(g.hinted.isEmpty)
        #expect(g.values == Self.puzzle)
    }

    @Test func codableRoundTrip() throws {
        var g = S.Game(puzzle: S.generate(difficulty: .hard, seed: 99))
        let open = (0..<81).filter { g.values[$0] == 0 }
        g.toggleNote(3, at: open[0])
        g.enter(g.puzzle.solution[open[1]], at: open[1])
        g.applyHint()
        g.erase(at: open[1])
        let data = try JSONEncoder().encode(g)
        var decoded = try JSONDecoder().decode(S.Game.self, from: data)
        #expect(decoded == g)
        // History survives too.
        decoded.undo()
        g.undo()
        #expect(decoded == g)
        #expect(decoded.values[open[1]] == g.puzzle.solution[open[1]])
    }
}
