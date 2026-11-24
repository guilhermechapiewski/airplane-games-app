extension DotsAndBoxes {
    /// Computer opponent strength.
    public enum Level: Int, CaseIterable, Codable, Sendable, Identifiable {
        case easy = 1, medium, hard

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .easy: "Easy"
            case .medium: "Medium"
            case .hard: "Hard"
            }
        }

        public var subtitle: String {
            switch self {
            case .easy: "Grabs boxes, otherwise plays at random"
            case .medium: "Careful not to give boxes away"
            case .hard: "Counts chains and fights for control"
            }
        }
    }

    public enum AI {
        /// Picks the computer's next line, or nil when the game is over.
        public static func chooseMove(for game: Game, level: Level, rng: inout SeededRandom) -> Line? {
            guard !game.isOver else { return nil }
            let g = Geometry(rows: game.rows, cols: game.cols)
            let p = Bits(game)
            let edge: Int
            switch level {
            case .easy: edge = easyMove(g, p, &rng)
            case .medium: edge = mediumMove(g, p, &rng)
            case .hard: edge = hardMove(g, p, &rng)
            }
            return game.line(at: edge)
        }

        public static func chooseMove(for game: Game, level: Level, seed: UInt64) -> Line? {
            var rng = SeededRandom(seed: seed)
            return chooseMove(for: game, level: level, rng: &rng)
        }

        /// With perfect play from here, the boxes still to be won by the player to move minus
        /// those won by the opponent. Only for positions without safe lines (the endgame);
        /// nil otherwise or when the search exceeds `budget` positions.
        public static func endgameValue(_ game: Game, budget: Int = 2_000_000) -> Int? {
            let g = Geometry(rows: game.rows, cols: game.cols)
            let p = Bits(game)
            guard g.safeEdges(p).isEmpty else { return nil }
            let solver = Solver(g, budget: budget)
            return try? solver.value(p)
        }

        // MARK: Easy

        static func easyMove(_ g: Geometry, _ p: Bits, _ rng: inout SeededRandom) -> Int {
            let captures = g.capturable(p).map { g.lastEdge($0, p) }
            if let edge = captures.randomElement(using: &rng) { return edge }
            return g.undrawn(p).randomElement(using: &rng)!
        }

        // MARK: Medium

        static func mediumMove(_ g: Geometry, _ p: Bits, _ rng: inout SeededRandom) -> Int {
            let captures = g.capturable(p).map { g.lastEdge($0, p) }
            if let edge = captures.randomElement(using: &rng) { return edge }
            if let edge = g.safeEdges(p).randomElement(using: &rng) { return edge }
            return smallestSacrifice(g, p, &rng)
        }

        /// The line that hands the opponent the fewest boxes, assuming they take everything.
        static func smallestSacrifice(_ g: Geometry, _ p: Bits, _ rng: inout SeededRandom) -> Int {
            var best: [Int] = []
            var bestCount = Int.max
            for edge in g.undrawn(p) {
                let (q, _) = g.apply(edge, p)
                let given = greedyCaptureCount(g, q)
                if given < bestCount {
                    bestCount = given
                    best = [edge]
                } else if given == bestCount {
                    best.append(edge)
                }
            }
            return best.randomElement(using: &rng)!
        }

        static func greedyCaptureCount(_ g: Geometry, _ p: Bits) -> Int {
            var q = p
            var count = 0
            while let box = g.capturable(q).first {
                let (next, completed) = g.apply(g.lastEdge(box, q), q)
                q = next
                count += completed
            }
            return count
        }

        // MARK: Hard

        /// Exact search once few safe lines remain; random safe lines before that.
        static func hardMove(_ g: Geometry, _ p: Bits, _ rng: inout SeededRandom) -> Int {
            let safeCount = g.safeEdges(p).count
            if safeCount <= searchSafeLimit(boxes: g.boxCount) {
                let solver = Solver(g, budget: 300_000)
                if let edge = try? solver.bestMove(p, &rng) { return edge }
            }
            return hardFallback(g, p, &rng)
        }

        /// How many safe lines may remain before Hard starts searching ahead (measured so a
        /// search nearly always finishes within its budget, a few hundred milliseconds).
        static func searchSafeLimit(boxes: Int) -> Int {
            boxes <= 9 ? 19 : (boxes <= 16 ? 15 : 7)
        }

        /// Used when the search would take too long: free boxes first, then a random safe line,
        /// then the smallest run (a two-box run is opened in the middle so it can't be declined).
        static func hardFallback(_ g: Geometry, _ p: Bits, _ rng: inout SeededRandom) -> Int {
            if let box = g.capturable(p).first { return g.lastEdge(box, p) }
            if let edge = g.safeEdges(p).randomElement(using: &rng) { return edge }
            let arms = g.arms(p).sorted { ($0.isLoop ? 2 : 1) * $0.boxes.count < ($1.isLoop ? 2 : 1) * $1.boxes.count }
            if let arm = arms.first { return arm.middle ?? arm.ends[0] }
            return smallestSacrifice(g, p, &rng)
        }
    }

    /// Negamax over positions with chain-aware move pruning: in a capture phase only one capture
    /// plus the "double-dealing" declines; once no safe lines remain, only canonical openings of
    /// each run (its ends, or the middle of a two-box run); before that, every safe line plus
    /// sacrifices of short runs.
    final class Solver {
        struct OutOfBudget: Error {}

        /// Known bounds on a position's value (alpha-beta leaves most positions inexact).
        private struct Bounds {
            var lower: Int8 = -127
            var upper: Int8 = 127
        }

        let g: Geometry
        let budget: Int
        private let full: Bits
        private var memo: [Bits: Bounds] = [:]
        private(set) var nodes = 0

        init(_ g: Geometry, budget: Int) {
            self.g = g
            self.budget = budget
            full = g.full
        }

        /// The best line, picked at random among equally good ones.
        func bestMove(_ p: Bits, _ rng: inout SeededRandom) throws -> Int {
            var best: [Int] = []
            var bestScore = -1000
            for edge in options(p) {
                // A window just below the best so far: worse lines are cut off, ties stay exact.
                let s = try score(edge, p, alpha: bestScore - 1, beta: 1000)
                if s > bestScore {
                    bestScore = s
                    best = [edge]
                } else if s == bestScore {
                    best.append(edge)
                }
            }
            return best.randomElement(using: &rng)!
        }

        /// Net future boxes for the player to move.
        func value(_ p: Bits) throws -> Int {
            try search(p, alpha: -1000, beta: 1000)
        }

        /// Fail-soft negamax with alpha-beta; exact when the result lies strictly inside the window.
        private func search(_ p: Bits, alpha: Int, beta: Int) throws -> Int {
            if p == full { return 0 }
            var alpha = alpha, beta = beta
            let known = memo[p] ?? Bounds()
            if known.lower == known.upper { return Int(known.lower) }
            if Int(known.lower) >= beta { return Int(known.lower) }
            if Int(known.upper) <= alpha { return Int(known.upper) }
            alpha = max(alpha, Int(known.lower))
            beta = min(beta, Int(known.upper))
            nodes += 1
            if nodes > budget { throw OutOfBudget() }
            var best = -1000
            for edge in options(p) {
                let s = try score(edge, p, alpha: max(alpha, best), beta: beta)
                if s > best {
                    best = s
                    if best >= beta { break }
                }
            }
            var bounds = known
            if best <= alpha {
                bounds.upper = min(bounds.upper, Int8(best))
            } else if best >= beta {
                bounds.lower = max(bounds.lower, Int8(best))
            } else {
                bounds.lower = Int8(best)
                bounds.upper = Int8(best)
            }
            memo[p] = bounds
            return best
        }

        private func score(_ edge: Int, _ p: Bits, alpha: Int, beta: Int) throws -> Int {
            let (q, completed) = g.apply(edge, p)
            if completed > 0 {
                return completed + (try search(q, alpha: alpha - completed, beta: beta - completed))
            }
            return -(try search(q, alpha: -beta, beta: -alpha))
        }

        func options(_ p: Bits) -> [Int] {
            let capturable = g.capturable(p)
            if !capturable.isEmpty {
                var declines: [Int] = []
                for a in capturable {
                    let e = g.lastEdge(a, p)
                    let b = g.across(e, from: a)
                    // A box that can't be part of a double-deal is always taken.
                    guard b >= 0, g.degree(b, p) == 2 else { return [e] }
                    // Declining: close the far side of the next box so both go to the opponent.
                    if let far = g.openEdges(b, p).first(where: { $0 != e }),
                       g.apply(far, p).1 == 0, !declines.contains(far) {
                        declines.append(far)
                    }
                }
                return [g.lastEdge(capturable[0], p)] + declines
            }
            let safe = g.safeEdges(p)
            var result = safe
            for arm in g.arms(p) {
                if !safe.isEmpty && (arm.isLoop || arm.boxes.count > 2) { continue }
                if let middle = arm.middle {
                    result.append(middle)
                } else {
                    result += arm.ends
                }
            }
            return result
        }
    }
}
