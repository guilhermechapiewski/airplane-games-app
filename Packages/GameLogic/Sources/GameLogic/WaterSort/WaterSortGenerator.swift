extension WaterSort {
    // MARK: Levels

    /// How many colors level `n` (1-based) uses: 3 at the start, one more every few levels, up to
    /// all 12 around level 60. From there levels vary between 10 and 12.
    public static func colorCount(forLevel n: Int) -> Int {
        let steps = [1, 3, 6, 10, 15, 21, 28, 36, 46, 58]   // first level with 3, 4, … 12 colors
        let level = max(1, n)
        if level < 60 {
            return 3 + (steps.lastIndex { $0 <= level } ?? 0)
        }
        var rng = SeededRandom(seed: levelSeed(level) ^ 0x5EED_C0105)
        return [10, 11, 11, 12, 12, 12][Int(rng.next() % 6)]
    }

    /// The puzzle of level `n`: the same for everyone, and always solvable.
    public static func level(_ n: Int) -> Puzzle {
        generate(colors: colorCount(forLevel: n), seed: levelSeed(max(1, n)))
    }

    /// Never change this: it would change everyone's levels.
    static func levelSeed(_ n: Int) -> UInt64 { SeededRandom.stableSeed("waterSort.level.\(n)") }

    // MARK: Generator

    /// A random, solvable puzzle with `colors` colors (each filling one tube) and two empty tubes.
    /// Deterministic for a seed: candidates are drawn from sub-seeds until the solver clears one.
    public static func generate(colors: Int, seed: UInt64, solverBudget: Int = 40_000) -> Puzzle {
        let colors = min(max(colors, 2), paletteSize)
        var attempt: UInt64 = 0
        while true {
            var rng = SeededRandom(seed: seed &+ attempt &* 0x9E37_79B9_7F4A_7C15)
            attempt += 1
            let tubes = candidate(colors: colors, using: &rng)
            guard isInteresting(tubes) else { continue }
            if Solver.solve(tubes, budget: solverBudget) != nil {
                return Puzzle(tubes: tubes)
            }
        }
    }

    private static func candidate(colors: Int, using rng: inout SeededRandom) -> [[Liquid]] {
        // Which of the palette's colors this puzzle uses, in random order.
        let liquids = Array(Array(0..<paletteSize).shuffled(using: &rng).prefix(colors))
        var layers = liquids.flatMap { Array(repeating: $0, count: capacity) }
        layers.shuffle(using: &rng)
        var tubes = stride(from: 0, to: layers.count, by: capacity).map { Array(layers[$0..<$0 + capacity]) }
        tubes += Array(repeating: [], count: emptyTubes)
        return tubes
    }

    /// No tube starts complete, and bigger puzzles don't start with long runs that sort themselves.
    private static func isInteresting(_ tubes: [[Liquid]]) -> Bool {
        let colors = tubes.filter { !$0.isEmpty }.count
        let maxRun = colors <= 4 ? 3 : 2
        for tube in tubes where !tube.isEmpty {
            if isComplete(tube) { return false }
            var run = 1
            for i in 1..<tube.count {
                run = tube[i] == tube[i - 1] ? run + 1 : 1
                if run > maxRun { return false }
            }
        }
        return true
    }

    // MARK: Solver

    /// Depth-first search over pours with a memo of positions already seen (tubes are
    /// interchangeable, so a position is keyed by its sorted tubes) and a node budget.
    public enum Solver {
        /// A sequence of pours that solves `tubes`, or nil if none was found within `budget` positions.
        public static func solve(_ tubes: [[Liquid]], budget: Int = 40_000) -> [Pour]? {
            var search = Search(budget: budget)
            var tubes = tubes
            var path: [Pour] = []
            return search.dfs(&tubes, &path) ? path : nil
        }
    }

    private struct Key: Hashable {
        var a: UInt64 = 0, b: UInt64 = 0, c: UInt64 = 0, d: UInt64 = 0

        init(_ tubes: [[Liquid]]) {
            var codes = tubes.map { tube -> UInt64 in
                var code: UInt64 = 0
                for (i, layer) in tube.enumerated() { code |= UInt64(layer + 1) << (4 * i) }
                return code
            }
            codes.sort()
            for (i, code) in codes.enumerated() {
                let shift = UInt64(16 * (i % 4))
                switch i / 4 {
                case 0: a |= code << shift
                case 1: b |= code << shift
                case 2: c |= code << shift
                default: d |= code << shift
                }
            }
        }
    }

    private struct Search {
        var budget: Int
        var seen: Set<Key> = []

        mutating func dfs(_ tubes: inout [[Liquid]], _ path: inout [Pour]) -> Bool {
            if tubes.allSatisfy({ $0.isEmpty || WaterSort.isComplete($0) }) { return true }
            guard budget > 0, seen.insert(Key(tubes)).inserted else { return false }
            budget -= 1
            for pour in candidates(tubes) {
                WaterSort.perform(pour, on: &tubes)
                path.append(pour)
                if dfs(&tubes, &path) { return true }
                path.removeLast()
                tubes[pour.to].removeLast(pour.count)
                tubes[pour.from].append(contentsOf: repeatElement(pour.liquid, count: pour.count))
            }
            return false
        }

        /// Useful pours, most promising first: whole runs onto the same color, then partial ones,
        /// then into a single empty tube (any empty tube is as good as another).
        func candidates(_ tubes: [[Liquid]]) -> [Pour] {
            var onColor: [Pour] = [], partial: [Pour] = [], intoEmpty: [Pour] = []
            let firstEmpty = tubes.firstIndex(where: \.isEmpty)
            for from in tubes.indices where !tubes[from].isEmpty && !WaterSort.isComplete(tubes[from]) {
                let run = WaterSort.topRun(tubes[from])
                let uniform = run == tubes[from].count
                for to in tubes.indices {
                    guard let pour = WaterSort.pour(from: from, to: to, in: tubes) else { continue }
                    if tubes[to].isEmpty {
                        if !uniform && to == firstEmpty { intoEmpty.append(pour) }
                    } else if pour.count == run {
                        onColor.append(pour)
                    } else {
                        partial.append(pour)
                    }
                }
            }
            return onColor + partial + intoEmpty
        }
    }
}
