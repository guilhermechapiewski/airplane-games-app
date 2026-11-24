import Foundation

extension TwentyFortyEight {
    /// Suggests a swipe with a shallow expectimax search: the player's moves are maximized, the
    /// random spawn (a 2 nine times in ten, otherwise a 4, in any empty cell) is averaged.
    ///
    /// Positions are scored the way strong players think: keep cells empty, keep merges ready,
    /// keep rows and columns monotonic (so the biggest tile settles in a corner), and avoid
    /// scattering big tiles.
    public enum Advisor {
        /// The best swipe, or nil when no swipe changes the board. Never suggests a no-op.
        /// `depth` is the number of player moves looked ahead (adapted down on open boards).
        public static func bestDirection(for state: State, depth: Int = 3) -> Direction? {
            let board = Board(state)
            var best: (Direction, Double)?
            // Open boards have many spawn spots and few dangers: a shallower search is plenty.
            let empties = board.cells.lazy.filter { $0 == 0 }.count
            let plies = empties > 6 ? min(depth, 2) : depth
            var memo: [Key: Double] = [:]
            for direction in Direction.searchOrder {
                guard let next = board.slid(direction) else { continue }
                // A merge banked now can't be lost to an unlucky spawn. The heuristic values a
                // ready merge more than a made one (it keeps the pair), so pay for making it here.
                let merges = Double(next.tileCount < board.tileCount ? board.tileCount - next.tileCount : 0)
                let value = chance(next, depth: plies - 1, memo: &memo) + merges * 2000
                if best == nil || value > best!.1 { best = (direction, value) }
            }
            return best?.0
        }

        /// Heuristic value of a board (higher is better). Exposed for tests.
        static func evaluate(_ state: State) -> Double { Board(state).heuristic }

        // MARK: Search

        private static func maxNode(_ board: Board, depth: Int, memo: inout [Key: Double]) -> Double {
            var best: Double?
            for direction in Direction.searchOrder {
                guard let next = board.slid(direction) else { continue }
                let v = chance(next, depth: depth - 1, memo: &memo)
                if best == nil || v > best! { best = v }
            }
            // No move left: the game is over here, which is the worst outcome.
            return best ?? -1e12
        }

        private static func chance(_ board: Board, depth: Int, memo: inout [Key: Double]) -> Double {
            if depth <= 0 { return board.heuristic }
            let key = Key(board: board, depth: depth)
            if let known = memo[key] { return known }
            let empties = board.cells.indices.filter { board.cells[$0] == 0 }
            guard !empties.isEmpty else { return board.heuristic }
            // With many empty cells a 4 rarely matters; skipping it keeps the search quick.
            let spawns: [(exponent: UInt8, weight: Double)] = empties.count > 6 ? [(1, 1)] : [(1, 0.9), (2, 0.1)]
            var total = 0.0
            for i in empties {
                for spawn in spawns {
                    var next = board
                    next.cells[i] = spawn.exponent
                    total += spawn.weight * maxNode(next, depth: depth, memo: &memo)
                }
            }
            let value = total / Double(empties.count)
            memo[key] = value
            return value
        }

        /// A chance node already averaged, with the plies left below it.
        private struct Key: Hashable {
            let board: Board
            let depth: Int
        }

        // MARK: Board

        /// A compact board: each cell holds log2 of its tile (0 = empty).
        struct Board: Hashable {
            let size: Int
            var cells: [UInt8]

            init(_ state: State) {
                size = state.size
                cells = state.valueGrid.flatMap { row in
                    row.map { $0 == 0 ? 0 : UInt8($0.trailingZeroBitCount) }
                }
            }

            private func index(line: Int, step: Int, direction: Direction) -> Int {
                switch direction {
                case .left: line * size + step
                case .right: line * size + (size - 1 - step)
                case .up: step * size + line
                case .down: (size - 1 - step) * size + line
                }
            }

            /// The board after sliding, or nil if nothing would move.
            func slid(_ direction: Direction) -> Board? {
                var out = self
                var moved = false
                var line = [UInt8](repeating: 0, count: size)
                for l in 0..<size {
                    var count = 0
                    for s in 0..<size {
                        let v = cells[index(line: l, step: s, direction: direction)]
                        if v != 0 { line[count] = v; count += 1 }
                    }
                    var target = 0
                    var i = 0
                    while i < count {
                        var v = line[i]
                        if i + 1 < count, line[i + 1] == v { v += 1; i += 2 } else { i += 1 }
                        let at = index(line: l, step: target, direction: direction)
                        if out.cells[at] != v { moved = true }
                        out.cells[at] = v
                        target += 1
                    }
                    for s in target..<size {
                        let at = index(line: l, step: s, direction: direction)
                        if out.cells[at] != 0 { moved = true }
                        out.cells[at] = 0
                    }
                }
                return moved ? out : nil
            }

            var tileCount: Int { cells.lazy.filter { $0 != 0 }.count }

            var heuristic: Double {
                var score = 0.0
                for l in 0..<size {
                    score += Self.lineScore((0..<size).map { cells[l * size + $0] })
                    score += Self.lineScore((0..<size).map { cells[$0 * size + l] })
                }
                return score
            }

            /// Rewards empty cells and ready merges; penalizes non-monotonic lines and big scattered tiles.
            private static func lineScore(_ line: [UInt8]) -> Double {
                var empty = 0.0, merges = 0.0, sum = 0.0
                var previous: UInt8 = 0, run = 0
                for v in line {
                    sum += pow(Double(v), 3.5)
                    if v == 0 { empty += 1; continue }
                    if v == previous {
                        run += 1
                    } else {
                        if run > 0 { merges += Double(1 + run) }
                        previous = v
                        run = 0
                    }
                }
                if run > 0 { merges += Double(1 + run) }
                var increasing = 0.0, decreasing = 0.0
                for i in 1..<line.count {
                    let a = pow(Double(line[i - 1]), 4), b = pow(Double(line[i]), 4)
                    if line[i - 1] > line[i] { increasing += a - b } else { decreasing += b - a }
                }
                return 270 * empty + 700 * merges - 47 * min(increasing, decreasing) - 11 * sum
            }
        }
    }
}

private extension Direction {
    /// Ties go to the first: the moves that keep big tiles in the bottom-left corner come first.
    static let searchOrder: [Direction] = [.left, .down, .right, .up]
}
