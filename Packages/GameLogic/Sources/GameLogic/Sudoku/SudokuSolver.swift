extension Sudoku {
    /// Solves a grid with bitmask backtracking. Returns `nil` if it has no solution.
    public static func solve(_ grid: [Int]) -> [Int]? {
        guard var solver = BitSolver(grid) else { return nil }
        var first: [Int]?
        _ = solver.count(limit: 1, first: &first)
        return first
    }

    /// Counts solutions of a grid, stopping early once `limit` is reached.
    /// `countSolutions(grid, limit: 2) == 1` ⇔ the puzzle is uniquely solvable.
    public static func countSolutions(_ grid: [Int], limit: Int = 2) -> Int {
        guard var solver = BitSolver(grid) else { return 0 }
        var first: [Int]?
        return solver.count(limit: limit, first: &first)
    }

    /// `true` when the grid has exactly one solution.
    public static func hasUniqueSolution(_ grid: [Int]) -> Bool {
        countSolutions(grid, limit: 2) == 1
    }

    /// A random, completely filled valid grid.
    static func randomSolution(using rng: inout SeededRandom) -> [Int] {
        var solver = BitSolver([Int](repeating: 0, count: cellCount))!
        _ = solver.fillRandomly(using: &rng)
        return solver.cells
    }
}

/// Depth-first solver over row/column/box digit masks with
/// minimum-remaining-values cell ordering.
struct BitSolver {
    private(set) var cells: [Int]
    private var rowMask = [UInt16](repeating: 0, count: 9)
    private var colMask = [UInt16](repeating: 0, count: 9)
    private var boxMask = [UInt16](repeating: 0, count: 9)
    private static let rowOf: [Int] = (0..<81).map { $0 / 9 }
    private static let colOf: [Int] = (0..<81).map { $0 % 9 }
    private static let boxOf: [Int] = (0..<81).map { Sudoku.box(of: $0) }

    /// Fails for malformed grids or grids whose givens already conflict.
    init?(_ grid: [Int]) {
        guard grid.count == Sudoku.cellCount else { return nil }
        cells = grid
        for i in 0..<81 where grid[i] != 0 {
            let d = grid[i]
            guard (1...9).contains(d) else { return nil }
            let b = Sudoku.bit(d)
            let r = i / 9, c = i % 9, x = Sudoku.box(of: i)
            if (rowMask[r] | colMask[c] | boxMask[x]) & b != 0 { return nil }
            rowMask[r] |= b; colMask[c] |= b; boxMask[x] |= b
        }
    }

    @inline(__always) private func free(_ i: Int) -> UInt16 {
        Sudoku.allDigits & ~(rowMask[Self.rowOf[i]] | colMask[Self.colOf[i]] | boxMask[Self.boxOf[i]])
    }

    @inline(__always) private mutating func toggle(_ i: Int, _ d: Int) {
        let b = Sudoku.bit(d)
        rowMask[Self.rowOf[i]] ^= b
        colMask[Self.colOf[i]] ^= b
        boxMask[Self.boxOf[i]] ^= b
    }

    /// The empty cell with the fewest candidates, or `nil` when the grid is full.
    private func mostConstrained() -> (cell: Int, mask: UInt16)? {
        var best = -1, bestMask: UInt16 = 0, bestCount = 10
        for i in 0..<81 where cells[i] == 0 {
            let m = free(i)
            let n = m.nonzeroBitCount
            if n < bestCount {
                best = i; bestMask = m; bestCount = n
                if n <= 1 { break }
            }
        }
        return best < 0 ? nil : (best, bestMask)
    }

    mutating func count(limit: Int, first: inout [Int]?) -> Int {
        var found = 0
        search(limit: limit, found: &found, first: &first)
        return found
    }

    private mutating func search(limit: Int, found: inout Int, first: inout [Int]?) {
        guard let (cell, mask) = mostConstrained() else {
            found += 1
            if first == nil { first = cells }
            return
        }
        var m = mask
        while m != 0 {
            let d = m.trailingZeroBitCount
            m &= m - 1
            cells[cell] = d
            toggle(cell, d)
            search(limit: limit, found: &found, first: &first)
            toggle(cell, d)
            cells[cell] = 0
            if found >= limit { return }
        }
    }

    /// Fills the grid, trying digits in random order. Returns `false` if unsolvable.
    mutating func fillRandomly(using rng: inout SeededRandom) -> Bool {
        guard let (cell, mask) = mostConstrained() else { return true }
        for d in Sudoku.digits(in: mask).shuffled(using: &rng) {
            cells[cell] = d
            toggle(cell, d)
            if fillRandomly(using: &rng) { return true }
            toggle(cell, d)
            cells[cell] = 0
        }
        return false
    }
}
