extension Nonograms {
    /// A pure line solver: repeatedly deduces every cell forced by a single row or column,
    /// considering all placements of that line's blocks. If it completes a grid, the puzzle
    /// is solvable without guessing — and therefore has exactly one solution.
    public enum Solver {
        public enum Cell: UInt8, Sendable {
            case unknown, filled, empty
        }

        public enum Result: Equatable, Sendable {
            /// Fully determined grid (row-major, `true` = filled).
            case solved([[Bool]])
            /// Line logic got stuck; `known` counts the cells it could determine.
            case stuck(known: Int)
            /// The clues contradict each other.
            case contradiction
        }

        /// Refines one line: returns the cells forced by every placement of `clue` that is
        /// consistent with `line`, or `nil` if no placement fits.
        public static func solveLine(clue: [Int], line: [Cell]) -> [Cell]? {
            let n = line.count
            let k = clue.count
            // suffixMin[j] = minimum length needed by blocks j..<k (with single gaps).
            var suffixMin = Array(repeating: 0, count: k + 1)
            for j in stride(from: k - 1, through: 0, by: -1) {
                suffixMin[j] = clue[j] + suffixMin[j + 1] + (j + 1 < k ? 1 : 0)
            }
            // prefixFilled[i] = number of filled cells in line[0..<i]: lets us test "no fill in range" in O(1).
            var prefixFilled = Array(repeating: 0, count: n + 1)
            var prefixEmpty = Array(repeating: 0, count: n + 1)
            for i in 0..<n {
                prefixFilled[i + 1] = prefixFilled[i] + (line[i] == .filled ? 1 : 0)
                prefixEmpty[i + 1] = prefixEmpty[i] + (line[i] == .empty ? 1 : 0)
            }
            func noFill(_ a: Int, _ b: Int) -> Bool { a >= b || prefixFilled[b] - prefixFilled[a] == 0 }
            func noEmpty(_ a: Int, _ b: Int) -> Bool { a >= b || prefixEmpty[b] - prefixEmpty[a] == 0 }

            // memo[i][j]: can blocks j..<k be placed in line[i..<n]?
            var memo = Array(repeating: Array(repeating: UInt8(2), count: k + 1), count: n + 2)
            func possible(_ i: Int, _ j: Int) -> Bool {
                if memo[i][j] != 2 { return memo[i][j] == 1 }
                var result = false
                if j == k {
                    result = noFill(i, n)
                } else {
                    let length = clue[j]
                    var s = i
                    while s + suffixMin[j] <= n {
                        if !noFill(i, s) { break }
                        let e = s + length
                        if noEmpty(s, e), e == n || line[e] != .filled, possible(min(n, e + 1), j + 1) {
                            result = true
                            break
                        }
                        s += 1
                    }
                }
                memo[i][j] = result ? 1 : 0
                return result
            }

            guard possible(0, 0) else { return nil }

            var canFill = Array(repeating: false, count: n)
            var canEmpty = Array(repeating: false, count: n)
            var visited = Set<Int>()
            var stack = [(0, 0)]
            while let (i, j) = stack.popLast() {
                guard visited.insert(i * (k + 1) + j).inserted else { continue }
                if j == k {
                    for x in i..<max(i, n) { canEmpty[x] = true }
                    continue
                }
                let length = clue[j]
                var s = i
                while s + suffixMin[j] <= n {
                    if !noFill(i, s) { break }
                    let e = s + length
                    let next = min(n, e + 1)
                    if noEmpty(s, e), e == n || line[e] != .filled, possible(next, j + 1) {
                        for x in i..<s { canEmpty[x] = true }
                        for x in s..<e { canFill[x] = true }
                        if e < n { canEmpty[e] = true }
                        stack.append((next, j + 1))
                    }
                    s += 1
                }
            }

            return (0..<n).map { x in
                switch (canFill[x], canEmpty[x]) {
                case (true, true): .unknown
                case (true, false): .filled
                default: .empty
                }
            }
        }

        /// Solves a puzzle from its clues using line logic only.
        public static func solve(rowClues: [[Int]], columnClues: [[Int]]) -> Result {
            let height = rowClues.count, width = columnClues.count
            var grid = Array(repeating: Array(repeating: Cell.unknown, count: width), count: height)
            var dirtyRows = Set(0..<height), dirtyColumns = Set(0..<width)

            while !dirtyRows.isEmpty || !dirtyColumns.isEmpty {
                for r in dirtyRows.sorted() {
                    guard let line = solveLine(clue: rowClues[r], line: grid[r]) else { return .contradiction }
                    for c in 0..<width where line[c] != grid[r][c] {
                        grid[r][c] = line[c]
                        dirtyColumns.insert(c)
                    }
                }
                dirtyRows.removeAll()
                for c in dirtyColumns.sorted() {
                    let column = (0..<height).map { grid[$0][c] }
                    guard let line = solveLine(clue: columnClues[c], line: column) else { return .contradiction }
                    for r in 0..<height where line[r] != grid[r][c] {
                        grid[r][c] = line[r]
                        dirtyRows.insert(r)
                    }
                }
                dirtyColumns.removeAll()
            }

            let known = grid.reduce(0) { $0 + $1.filter { $0 != .unknown }.count }
            guard known == width * height else { return .stuck(known: known) }
            return .solved(grid.map { $0.map { $0 == .filled } })
        }

        public static func solve(_ puzzle: Puzzle) -> Result {
            solve(rowClues: puzzle.rowClues, columnClues: puzzle.columnClues)
        }

        /// Whether the puzzle has a unique solution reachable by line logic alone.
        public static func isLineSolvable(_ puzzle: Puzzle) -> Bool {
            guard case .solved(let grid) = solve(puzzle) else { return false }
            return grid.flatMap { $0 } == puzzle.solution
        }
    }
}
