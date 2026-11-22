extension Minesweeper {
    /// Decides whether a board can be cleared by logic alone, the way a careful player would:
    /// no step ever needs a guess.
    ///
    /// It applies, until nothing changes:
    /// 1. **Single clues**: a number whose mines are all found makes its other hidden neighbours
    ///    safe; a number with exactly as many hidden neighbours as missing mines makes them all mines.
    /// 2. **Pairs of overlapping clues** (e.g. 1-2-1 patterns): if clue A needs more mines in the
    ///    cells only it sees than clue B could take, those cells are mines and B's own cells are safe;
    ///    a clue whose cells contain another clue's cells with the same count makes the rest safe.
    /// 3. **The mine count**, once the clues are exhausted: no mines left means every hidden cell
    ///    is safe; as many mines left as hidden cells means every one is a mine.
    ///
    /// The solver never looks at where the mines are except to read the numbers a real reveal
    /// would show. A `true` answer is a guarantee; `false` means "these rules get stuck", which
    /// can reject a few boards an expert could still finish.
    public enum Solver {
        /// Whether the board can be cleared by logic after the player reveals `start`.
        public static func solvesWithoutGuessing(_ board: State, from start: GridPoint) -> Bool {
            solvesWithoutGuessing(board, opened: [start])
        }

        /// Whether the board can be cleared by logic once the `opened` cells are revealed.
        public static func solvesWithoutGuessing(_ board: State, opened: [GridPoint]) -> Bool {
            var grid = Grid(board)
            for p in opened {
                guard !grid.isMine[grid.index(p)] else { return false }
                grid.reveal(grid.index(p))
            }
            return grid.solve()
        }
    }
}

/// A flat working copy of a board: what the player knows, and the mines (only read through
/// the numbers a reveal would show).
private struct Grid {
    enum Known: UInt8 { case unknown, safe, mine }

    let rows: Int
    let cols: Int
    let isMine: [Bool]
    let adjacent: [Int]
    let neighbors: [[Int]]
    let mineCount: Int
    var known: [Known]
    var safeLeft: Int
    var minesFound = 0

    init(_ board: Minesweeper.State) {
        rows = board.rows
        cols = board.cols
        let points = board.allPoints
        isMine = points.map { board[$0].isMine }
        adjacent = points.map { board[$0].adjacent }
        neighbors = points.map { p in board.neighbors(of: p).map { $0.row * board.cols + $0.col } }
        mineCount = board.mineCount
        known = Array(repeating: .unknown, count: points.count)
        safeLeft = points.count - board.mineCount
    }

    func index(_ p: GridPoint) -> Int { p.row * cols + p.col }

    /// Opens a safe cell, flooding through zeros like the game does.
    mutating func reveal(_ start: Int) {
        guard known[start] == .unknown else { return }
        var stack = [start]
        known[start] = .safe
        safeLeft -= 1
        while let i = stack.popLast() {
            guard adjacent[i] == 0 else { continue }
            for n in neighbors[i] where known[n] == .unknown {
                known[n] = .safe
                safeLeft -= 1
                stack.append(n)
            }
        }
    }

    mutating func markMine(_ i: Int) {
        guard known[i] == .unknown else { return }
        known[i] = .mine
        minesFound += 1
    }

    /// A revealed number's hidden neighbours and how many of them are mines.
    struct Clue {
        var cells: [Int]
        var mines: Int
    }

    func clue(at i: Int) -> Clue? {
        guard known[i] == .safe, adjacent[i] > 0 else { return nil }
        var hidden: [Int] = []
        var flagged = 0
        for n in neighbors[i] {
            switch known[n] {
            case .unknown: hidden.append(n)
            case .mine: flagged += 1
            case .safe: break
            }
        }
        return hidden.isEmpty ? nil : Clue(cells: hidden, mines: adjacent[i] - flagged)
    }

    /// Applies the rules until the board is clear (true) or nothing more can be deduced (false).
    mutating func solve() -> Bool {
        while safeLeft > 0 {
            if applySingleClues() || applyCluePairs() || applyMineCount() { continue }
            return false
        }
        return true
    }

    private mutating func applySingleClues() -> Bool {
        var progress = false
        for i in known.indices {
            guard let c = clue(at: i) else { continue }
            if c.mines == 0 {
                for n in c.cells { reveal(n) }
                progress = true
            } else if c.mines == c.cells.count {
                for n in c.cells { markMine(n) }
                progress = true
            }
        }
        return progress
    }

    private mutating func applyCluePairs() -> Bool {
        let clues = known.indices.compactMap { clue(at: $0) }
        // Index clues by the hidden cells they see, so only clues that share a cell are compared.
        var byCell: [Int: [Int]] = [:]
        for (k, c) in clues.enumerated() { for cell in c.cells { byCell[cell, default: []].append(k) } }
        for (a, ca) in clues.enumerated() {
            let setA = Set(ca.cells)
            var partners = Set<Int>()
            for cell in ca.cells { partners.formUnion(byCell[cell] ?? []) }
            for b in partners where b != a {
                let cb = clues[b]
                let setB = Set(cb.cells)
                let onlyA = setA.subtracting(setB)
                let onlyB = setB.subtracting(setA)
                // A needs more mines than the shared cells can hold beyond B's count:
                // its own cells are all mines, and B's own cells are all safe.
                if !onlyA.isEmpty, ca.mines - cb.mines == onlyA.count {
                    for n in onlyA { markMine(n) }
                    for n in onlyB { reveal(n) }
                    return true
                }
                // A's cells all lie inside B's and both need the same number: B's extra cells are safe.
                if onlyA.isEmpty, !onlyB.isEmpty, ca.mines == cb.mines {
                    for n in onlyB { reveal(n) }
                    return true
                }
            }
        }
        return false
    }

    private mutating func applyMineCount() -> Bool {
        let hidden = known.indices.filter { known[$0] == .unknown }
        guard !hidden.isEmpty else { return false }
        let left = mineCount - minesFound
        if left == 0 {
            for n in hidden { reveal(n) }
            return true
        }
        if left == hidden.count {
            for n in hidden { markMine(n) }
            return true
        }
        return false
    }
}
