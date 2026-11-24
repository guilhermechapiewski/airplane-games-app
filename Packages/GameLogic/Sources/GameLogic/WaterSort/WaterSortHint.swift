extension WaterSort {
    /// What to do next, found by solving from the current position.
    public enum Hint: Equatable, Sendable {
        /// Pour this next; the puzzle can still be sorted from here.
        case pour(Pour)
        /// It can't be sorted with these tubes, but it can with the extra one.
        case addExtraTube
        /// It can't be sorted from here; taking back `steps` pours gets back on track.
        case undo(steps: Int)
        /// No way found from here or from any earlier position: start over.
        case restart
    }

    /// Nodes the solver may visit per position. Hints run off the main thread, so they can afford
    /// a bigger search than level generation.
    public static let hintBudget = 150_000

    /// How far back a hint looks for a position that can still be sorted.
    static let maxUndoSearch = 40

    /// Gives hints that stick to one solution: as long as the player follows them, the next hint
    /// continues the same plan instead of solving afresh (a fresh search could wander back and forth).
    public struct HintPlanner: Equatable, Sendable {
        /// The rest of the plan, starting from `tubes`.
        private var plan: [Pour] = []
        private var tubes: [[Liquid]] = []

        public init() {}

        /// The next step from `state`, or nil once it's sorted. Can take a moment on big puzzles:
        /// call it off the main actor.
        public mutating func hint(for state: State, budget: Int = hintBudget) -> Hint? {
            guard !state.isSolved else { return nil }
            if !plan.isEmpty, tubes != state.tubes {
                // The player took the suggested pour: move along the plan.
                var next = tubes
                WaterSort.perform(plan[0], on: &next)
                if next == state.tubes {
                    plan.removeFirst()
                    tubes = next
                } else {
                    plan = []
                }
            }
            if plan.isEmpty || tubes != state.tubes {
                plan = Solver.solve(state.tubes, budget: budget) ?? []
                tubes = state.tubes
            }
            if let first = plan.first { return .pour(first) }
            return Self.recovery(from: state, budget: budget)
        }

        /// When no solution is found from the current position.
        static func recovery(from state: State, budget: Int) -> Hint {
            if !state.extraTubeUsed, Solver.solve(state.tubes + [[]], budget: budget) != nil {
                return .addExtraTube
            }
            // Walk back through the pours made for the latest position that can still be sorted
            // (undo keeps the extra tube once it has been added).
            var earlier = state
            for steps in 0..<min(state.history.count, maxUndoSearch) {
                earlier.undo()
                if Solver.solve(earlier.tubes, budget: budget / 4) != nil {
                    return .undo(steps: steps + 1)
                }
            }
            return .restart
        }
    }
}

extension WaterSort.State {
    /// The next step towards a sorted board, or nil once it's sorted (see `HintPlanner` to keep
    /// successive hints on one plan). Can take a moment on big puzzles: call it off the main actor.
    public func hint(budget: Int = WaterSort.hintBudget) -> WaterSort.Hint? {
        var planner = WaterSort.HintPlanner()
        return planner.hint(for: self, budget: budget)
    }
}
