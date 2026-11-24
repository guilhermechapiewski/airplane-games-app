import Foundation
import Testing
@testable import GameLogic

@Suite("Water Sort hints")
struct WaterSortHintTests {
    typealias W = WaterSort

    @Test func noHintOnceSorted() {
        let s = W.State(tubes: [[0, 0, 0, 0], [1, 1, 1, 1], []])
        #expect(s.isSolved)
        #expect(s.hint() == nil)
    }

    @Test func suggestsTheFinishingPour() throws {
        var s = W.State(tubes: [[0, 0, 0, 0], [5, 5, 5], [5], [], [7, 7, 7, 7]])
        guard case let .pour(pour) = s.hint() else {
            Issue.record("expected a pour")
            return
        }
        #expect(s.apply(from: pour.from, to: pour.to) != nil)
        #expect(s.isSolved)
    }

    @Test func suggestsTheExtraTubeWhenOnlyItHelps() {
        // Two interleaved tubes and nowhere to pour: hopeless without more room.
        let s = W.State(tubes: [[0, 1, 0, 1], [1, 0, 1, 0]])
        #expect(W.Solver.solve(s.tubes) == nil)
        #expect(s.hint() == .addExtraTube)

        var withExtra = s
        withExtra.addExtraTube()
        #expect(withExtra.hint().map { if case .pour = $0 { true } else { false } } == true)
    }

    @Test func suggestsRestartWhenNothingHelps() {
        // Single layers can never fill a tube, there's nothing to undo and the extra tube is in use.
        var used = W.State(tubes: [[0, 1], []])
        used.addExtraTube()
        #expect(W.Solver.solve(used.tubes, budget: W.hintBudget) == nil)
        #expect(used.hint() == .restart)
    }

    /// After a few careless pours the puzzle can't be sorted any more: the hint says how many
    /// pours to take back, and that many undos really is the latest position that works.
    @Test func suggestsHowFarToUndo() {
        var checked = 0
        for seed in 1...200 as ClosedRange<UInt64> where checked < 3 {
            var rng = SeededRandom(seed: seed)
            var s = W.State(puzzle: W.generate(colors: 9, seed: seed))
            s.addExtraTube()
            for _ in 0..<80 {
                let pours = s.usefulPours
                guard !pours.isEmpty, !s.isSolved else { break }
                let p = pours[Int(rng.next() % UInt64(pours.count))]
                s.apply(from: p.from, to: p.to)
                guard !s.isSolved, W.Solver.solve(s.tubes, budget: W.hintBudget) == nil else { continue }
                guard case let .undo(steps) = s.hint() else {
                    Issue.record("seed \(seed): expected an undo hint, got \(String(describing: s.hint()))")
                    return
                }
                var back = s
                for _ in 0..<steps { back.undo() }
                #expect(W.Solver.solve(back.tubes) != nil)
                var almost = s
                for _ in 0..<(steps - 1) { almost.undo() }
                #expect(steps == 1 || W.Solver.solve(almost.tubes, budget: W.hintBudget) == nil)
                checked += 1
                break
            }
        }
        #expect(checked == 3, "only \(checked) dead ends found to test")
    }

    /// Following the hints sorts a big level from the start.
    @Test func followingHintsSolves() {
        var s = W.State(puzzle: W.level(60))
        var planner = W.HintPlanner()
        var pours = 0
        while !s.isSolved, pours < 400, case let .pour(p) = planner.hint(for: s) {
            #expect(s.apply(from: p.from, to: p.to) != nil)
            pours += 1
        }
        #expect(s.isSolved, "\(pours) pours, last hint \(String(describing: s.hint()))")
    }

    @Test func plannerReplansWhenThePlayerGoesTheirOwnWay() {
        var s = W.State(puzzle: W.level(30))
        var planner = W.HintPlanner()
        guard case let .pour(first) = planner.hint(for: s) else {
            Issue.record("expected a pour")
            return
        }
        // Pour something else instead.
        let other = s.usefulPours.first { $0 != first }!
        s.apply(from: other.from, to: other.to)
        guard case let .pour(next) = planner.hint(for: s) else {
            Issue.record("expected a pour (or a way back) after going off-plan")
            return
        }
        #expect(s.usefulPours.contains(next))
    }

    @Test func hintsFromAMidGamePosition() {
        // Partway into a big level (following the solver), every hint is a legal, useful pour.
        var s = W.State(puzzle: W.level(45))
        let path = W.Solver.solve(s.tubes) ?? []
        for p in path.prefix(path.count / 2) { s.apply(from: p.from, to: p.to) }
        guard case let .pour(p) = s.hint() else {
            Issue.record("expected a pour")
            return
        }
        #expect(s.usefulPours.contains(p))
    }
}
