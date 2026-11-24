import Foundation
import Testing
@testable import GameLogic

@Suite("Water Sort")
struct WaterSortTests {
    typealias W = WaterSort

    /// Replays pours; true if each is legal and the puzzle ends solved.
    func replays(_ tubes: [[Int]], _ pours: [W.Pour]) -> Bool {
        var state = W.State(tubes: tubes)
        for pour in pours {
            guard state.apply(from: pour.from, to: pour.to) == pour else { return false }
        }
        return state.isSolved
    }

    func checkWellFormed(_ puzzle: W.Puzzle, colors: Int) {
        #expect(puzzle.colorCount == colors)
        #expect(puzzle.tubes.count == colors + W.emptyTubes)
        #expect(puzzle.tubes.filter(\.isEmpty).count == W.emptyTubes)
        for tube in puzzle.tubes where !tube.isEmpty {
            #expect(tube.count == W.capacity)
            #expect(!W.isComplete(tube), "no tube starts complete")
        }
        let counts = Dictionary(grouping: puzzle.tubes.joined(), by: { $0 }).mapValues(\.count)
        #expect(counts.values.allSatisfy { $0 == W.capacity }, "each color fills exactly one tube")
        #expect(counts.keys.allSatisfy { (0..<W.paletteSize).contains($0) })
    }

    // MARK: Pour rules

    @Test func poursTheWholeTopRunOntoAnEmptyTube() {
        var s = W.State(tubes: [[0, 1, 2, 2], []])
        let pour = s.apply(from: 0, to: 1)
        #expect(pour == W.Pour(from: 0, to: 1, count: 2, liquid: 2))
        #expect(s.tubes == [[0, 1], [2, 2]])
        #expect(s.moveCount == 1)
    }

    @Test func poursOnlyOntoTheSameColor() {
        let s = W.State(tubes: [[0, 1], [0, 2], [1]])
        #expect(!s.canPour(from: 0, to: 1), "blue can't go on green")
        #expect(s.pour(from: 0, to: 2) == W.Pour(from: 0, to: 2, count: 1, liquid: 1))
    }

    @Test func poursAsMuchAsFits() {
        var s = W.State(tubes: [[0, 1, 1, 1], [2, 2, 1]])
        let pour = s.apply(from: 0, to: 1)
        #expect(pour?.count == 1, "only one layer of room")
        #expect(s.tubes == [[0, 1, 1], [2, 2, 1, 1]])
    }

    @Test func illegalPours() {
        let s = W.State(tubes: [[], [0, 0, 0, 0], [0, 1, 0, 1], [1]])
        #expect(!s.canPour(from: 0, to: 3), "an empty tube has nothing to pour")
        #expect(!s.canPour(from: 2, to: 2), "a tube can't pour into itself")
        #expect(!s.canPour(from: 3, to: 2), "full tube")
        #expect(!s.canPour(from: 3, to: 1), "full tube")
        #expect(s.pour(from: 9, to: 0) == nil, "out of range")
        var t = s
        #expect(t.apply(from: 3, to: 2) == nil)
        #expect(t == s, "a rejected pour changes nothing")
    }

    @Test func completionAndSolved() {
        let s = W.State(tubes: [[0, 0, 0, 0], [1, 1, 1], [1], []])
        #expect(s.isComplete(0))
        #expect(!s.isComplete(1), "not full")
        #expect(!s.canPick(0), "complete tubes stay put")
        #expect(!s.canPick(3), "empty tubes have nothing to pick")
        #expect(s.canPick(1))
        #expect(!s.isSolved)
        var t = s
        t.apply(from: 2, to: 1)
        #expect(t.isSolved)
        #expect(!t.isStuck)
    }

    @Test func targetsListsLegalDestinations() {
        let s = W.State(tubes: [[0, 1], [2, 1], [], [1, 1, 1, 1]])
        #expect(s.targets(from: 0) == [1, 2])
        #expect(s.targets(from: 2) == [])
    }

    @Test func stuckWhenNoUsefulPourIsLeft() {
        // Full mixed tubes, no room anywhere.
        let full = W.State(tubes: [[0, 1, 0, 1], [1, 0, 1, 0]])
        #expect(full.isStuck)
        // Only shuffling a single-colored tube into an empty one is possible: still stuck.
        let onlyUniformToEmpty = W.State(tubes: [[0, 0], [1, 1, 1], []])
        #expect(onlyUniformToEmpty.isStuck)
        // An empty tube with a mixed tube beside it is a way out.
        let free = W.State(tubes: [[0, 1, 0, 1], []])
        #expect(!free.isStuck)
    }

    // MARK: Undo, extra tube, restart

    @Test func undoRestoresEachStep() {
        var s = W.State(tubes: [[0, 1, 1], [2, 1], [], [0, 2]])
        let start = s
        var snapshots = [s.tubes]
        for (from, to) in [(0, 2), (1, 2), (3, 1), (3, 0)] {
            #expect(s.apply(from: from, to: to) != nil)
            snapshots.append(s.tubes)
        }
        #expect(s.moveCount == 4)
        while s.canUndo {
            snapshots.removeLast()
            s.undo()
            #expect(s.tubes == snapshots.last)
        }
        #expect(s == start)
        #expect(s.undo() == nil)
    }

    @Test func extraTubeOncePerPuzzle() {
        var s = W.State(tubes: [[0, 1, 0, 1], [1, 0, 1, 0]])
        #expect(s.isStuck)
        let added = s.addExtraTube()
        #expect(added)
        #expect(s.extraTubeUsed)
        #expect(s.tubes.count == 3)
        #expect(!s.isStuck)
        let again = s.addExtraTube()
        #expect(!again, "only one")
        #expect(s.tubes.count == 3)
        s.apply(from: 0, to: 2)
        s.undo()
        #expect(s.tubes.count == 3, "undo keeps the extra tube")
        s.apply(from: 0, to: 2)
        s.restart()
        #expect(s.tubes == s.puzzle.tubes)
        #expect(!s.extraTubeUsed)
        #expect(s.history.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var s = W.State(puzzle: W.level(12))
        s.addExtraTube()
        let pours = s.usefulPours.prefix(3)
        for pour in pours where s.canPour(from: pour.from, to: pour.to) {
            s.apply(from: pour.from, to: pour.to)
        }
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(W.State.self, from: data)
        #expect(decoded == s)
        #expect(decoded.history == s.history)
        #expect(decoded.extraTubeUsed)
    }

    // MARK: Generator & solver

    @Test func solverSolvesAndReplays() throws {
        let tubes = [[0, 1, 0, 1], [1, 0, 1, 0], [], []]
        let pours = try #require(W.Solver.solve(tubes))
        #expect(replays(tubes, pours))
    }

    @Test func solverReportsUnsolvable() {
        #expect(W.Solver.solve([[0, 1, 0, 1], [1, 0, 1, 0]]) == nil)
        #expect(W.Solver.solve([[0, 0, 0, 0], []]) == [], "already solved")
    }

    @Test func colorCountsRampGently() {
        #expect(W.colorCount(forLevel: 1) == 3)
        #expect(W.colorCount(forLevel: 0) == 3)
        #expect(W.colorCount(forLevel: 3) == 4)
        #expect(W.colorCount(forLevel: 30) == 9)
        #expect(W.colorCount(forLevel: 59) == 12)
        var previous = 3
        for n in 1..<60 {
            let c = W.colorCount(forLevel: n)
            #expect(c == previous || c == previous + 1, "level \(n)")
            previous = c
        }
        let late = (60..<200).map(W.colorCount(forLevel:))
        #expect(late.allSatisfy { (10...12).contains($0) })
        #expect(Set(late).count > 1, "later levels vary")
    }

    @Test func levelsAreDeterministic() {
        #expect(W.level(7) == W.level(7))
        #expect(W.level(7) != W.level(8))
        #expect(W.daily(seed: 42) == W.daily(seed: 42))
        // Pinned so an accidental change to the generator (which would change everyone's levels) shows up.
        #expect(W.level(1).tubes.count == 5)
    }

    @Test func levelsOneToHundredAreSolvable() throws {
        for n in 1...100 {
            let puzzle = W.level(n)
            checkWellFormed(puzzle, colors: W.colorCount(forLevel: n))
            let pours = try #require(W.Solver.solve(puzzle.tubes, budget: 200_000), "level \(n)")
            #expect(replays(puzzle.tubes, pours), "level \(n)")
        }
    }

    @Test func dailiesAreSolvableAndMediumHard() throws {
        var day = Daily.Day(year: 2026, month: 11, day: 1)
        for _ in 0..<20 {
            let seed = Daily.seed(day: day, game: "waterSort")
            let puzzle = W.daily(seed: seed)
            let colors = W.dailyColorCount(seed: seed)
            #expect((8...9).contains(colors))
            checkWellFormed(puzzle, colors: colors)
            let pours = try #require(W.Solver.solve(puzzle.tubes, budget: 200_000), "\(day.key)")
            #expect(replays(puzzle.tubes, pours))
            day = day.next
        }
    }

    @Test func hardestLevelsGenerateQuickly() {
        let start = threadCPUTime()
        for n in 200..<220 { _ = W.level(n) }
        let perLevel = (threadCPUTime() - start) / 20
        #expect(perLevel < 0.15, "\(perLevel)s per level")
    }
}
