extension FreeCell {
    /// A best-first FreeCell solver, used to check that deals can be won and to give hints.
    ///
    /// Positions are compact (card ids as bytes); safe foundation plays are made automatically
    /// after every move (the same rule as `State.nextSafeMove`), and positions are recognised
    /// regardless of the order of the free cells and the columns. The search is deterministic.
    public enum Solver {
        public enum Status: Sendable, Equatable {
            /// A winning line was found.
            case solved
            /// Every reachable position was tried: no win from here.
            case unsolvable
            /// Gave up after the node budget.
            case gaveUp
        }

        public struct Result: Sendable {
            public var status: Status
            /// Moves from the starting position to a won game (when solved), including the
            /// automatic foundation plays.
            public var moves: [Move]
            public var nodes: Int
            public var solved: Bool { status == .solved }
        }

        public static let defaultBudget = 40_000

        /// Searches until a win is found, every position is tried, `nodeBudget` positions are
        /// expanded, or `timeLimit` passes (unoptimized builds are ~35× slower, so hints cap time too).
        public static func solve(_ start: State, nodeBudget: Int = defaultBudget, timeLimit: Duration? = nil) -> Result {
            let clock = ContinuousClock()
            let deadline = timeLimit.map { clock.now + $0 }
            var root = FreeCellPosition(start)
            var rootMoves: [Move] = []
            root.playSafe(into: &rootMoves)
            if root.isDone {
                return Result(status: .solved, moves: rootMoves + root.finish(), nodes: 0)
            }

            struct Closed {
                var position: FreeCellPosition
                var parent: Int32
                var moves: [Move]
            }
            struct Open: Comparable {
                var priority: Int32
                var order: Int32
                var parent: Int32
                var move: Move
                static func < (a: Open, b: Open) -> Bool {
                    a.priority != b.priority ? a.priority < b.priority : a.order > b.order
                }
            }

            var closed: [Closed] = [Closed(position: root, parent: -1, moves: rootMoves)]
            var visited: Set<UInt64> = [root.key]
            var heap = FreeCellHeap<Open>()
            var order: Int32 = 0
            var nodes = 0

            func expand(_ index: Int) {
                let position = closed[index].position
                for move in position.moves() {
                    var child = position
                    child.apply(move)
                    var auto: [Move] = []
                    child.playSafe(into: &auto)
                    guard visited.insert(child.key).inserted else { continue }
                    order += 1
                    heap.push(Open(priority: Int32(child.heuristic), order: order, parent: Int32(index), move: move))
                }
            }

            expand(0)
            while let next = heap.pop() {
                if nodes >= nodeBudget { return Result(status: .gaveUp, moves: [], nodes: nodes) }
                if let deadline, nodes % 256 == 0, clock.now >= deadline {
                    return Result(status: .gaveUp, moves: [], nodes: nodes)
                }
                nodes += 1
                var position = closed[Int(next.parent)].position
                var moves = [next.move]
                position.apply(next.move)
                position.playSafe(into: &moves)
                closed.append(Closed(position: position, parent: next.parent, moves: moves))
                let index = closed.count - 1
                if position.isDone {
                    var path = position.finish()
                    var i = index
                    while i >= 0 {
                        path.insert(contentsOf: closed[i].moves, at: 0)
                        i = Int(closed[i].parent)
                    }
                    return Result(status: .solved, moves: path, nodes: nodes)
                }
                expand(index)
            }
            return Result(status: .unsolvable, moves: [], nodes: nodes)
        }
    }

    /// What the Hint button suggests.
    public enum Hint: Equatable, Sendable {
        /// Play this move: it starts a winning line.
        case move(Move)
        /// No winning line exists from here.
        case noSolution
        /// The search ran out of budget without an answer.
        case unknown
    }

    /// The first move of a winning line from `state`, if there is one.
    public static func hint(for state: State, nodeBudget: Int = Solver.defaultBudget) -> Hint {
        guard !state.isWon else { return .noSolution }
        let result = Solver.solve(state, nodeBudget: nodeBudget)
        switch result.status {
        case .solved: return result.moves.first.map(Hint.move) ?? .noSolution
        case .unsolvable: return .noSolution
        case .gaveUp: return .unknown
        }
    }

    /// The first deal at or after `number` (wrapping around) that the solver can win, with its solution.
    public static func solvableDeal(startingAt number: Int, nodeBudget: Int = Solver.defaultBudget,
                                    shouldContinue: () -> Bool = { true }) -> (state: State, solution: [Move])? {
        var n = normalizedDeal(number)
        for _ in 0..<200 {
            guard shouldContinue() else { return nil }
            let state = State.deal(number: n)
            let result = Solver.solve(state, nodeBudget: nodeBudget)
            if result.solved { return (state, result.moves) }
            n = normalizedDeal(n + 1)
        }
        return nil
    }
}

// MARK: - Compact position

/// The solver's own position: card ids (0...51) as bytes.
struct FreeCellPosition {
    static let empty: UInt8 = 0xFF
    var cols: [[UInt8]]
    var cells: [UInt8]
    var found: [UInt8]

    init(_ state: FreeCell.State) {
        cols = state.tableau.map { $0.map { UInt8($0.id) } }
        cells = state.cells.map { $0.map { UInt8($0.id) } ?? Self.empty }
        found = state.foundations.map(UInt8.init)
    }

    @inline(__always) static func rank(_ c: UInt8) -> Int { Int(c % 13) + 1 }
    @inline(__always) static func suit(_ c: UInt8) -> Int { Int(c / 13) }
    @inline(__always) static func isRed(_ c: UInt8) -> Bool { let s = c / 13; return s == 1 || s == 2 }
    @inline(__always) static func stacks(_ a: UInt8, on b: UInt8) -> Bool {
        rank(a) + 1 == rank(b) && isRed(a) != isRed(b)
    }

    var freeCells: Int { cells.reduce(0) { $0 + ($1 == Self.empty ? 1 : 0) } }
    var emptyCols: Int { cols.reduce(0) { $0 + ($1.isEmpty ? 1 : 0) } }
    var isWon: Bool { found.allSatisfy { $0 == 13 } }

    /// Won, or every column is in descending order so the rest plays off.
    var isDone: Bool {
        for col in cols where col.count > 1 {
            for i in 1..<col.count where Self.rank(col[i]) > Self.rank(col[i - 1]) { return false }
        }
        return true
    }

    func canFound(_ c: UInt8) -> Bool { Int(found[Self.suit(c)]) == Self.rank(c) - 1 }

    func isSafe(_ c: UInt8) -> Bool {
        guard canFound(c) else { return false }
        let r = Self.rank(c)
        if r <= 2 { return true }
        let red = Self.isRed(c)
        for s in 0..<4 where (s == 1 || s == 2) != red {
            if Int(found[s]) < r - 1 { return false }
        }
        return true
    }

    /// Same order as `State.nextSafeMove`.
    mutating func playSafe(into moves: inout [FreeCell.Move]) {
        var progress = true
        while progress {
            progress = false
            for i in 0..<cells.count where cells[i] != Self.empty && isSafe(cells[i]) {
                let s = Self.suit(cells[i])
                moves.append(.init(from: .cell(i), to: .foundation(s)))
                found[s] += 1
                cells[i] = Self.empty
                progress = true
                break
            }
            if progress { continue }
            for t in 0..<cols.count {
                if let c = cols[t].last, isSafe(c) {
                    let s = Self.suit(c)
                    moves.append(.init(from: .tableau(t), to: .foundation(s)))
                    found[s] += 1
                    cols[t].removeLast()
                    progress = true
                    break
                }
            }
        }
    }

    /// Plays everything off a done position, lowest card first.
    mutating func finish() -> [FreeCell.Move] {
        var moves: [FreeCell.Move] = []
        while !isWon {
            var best: (FreeCell.Move, Int)?
            for i in 0..<cells.count where cells[i] != Self.empty && canFound(cells[i]) {
                let r = Self.rank(cells[i])
                if r < (best?.1 ?? 99) { best = (.init(from: .cell(i), to: .foundation(Self.suit(cells[i]))), r) }
            }
            for t in 0..<cols.count {
                if let c = cols[t].last, canFound(c), Self.rank(c) < (best?.1 ?? 99) {
                    best = (.init(from: .tableau(t), to: .foundation(Self.suit(c))), Self.rank(c))
                }
            }
            guard let move = best?.0 else { break }
            apply(move)
            moves.append(move)
        }
        return moves
    }

    func runLength(_ t: Int) -> Int {
        let col = cols[t]
        guard !col.isEmpty else { return 0 }
        var n = 1
        while n < col.count, Self.stacks(col[col.count - n], on: col[col.count - n - 1]) { n += 1 }
        return n
    }

    mutating func apply(_ move: FreeCell.Move) {
        var moving: [UInt8]
        switch move.from {
        case .cell(let i):
            moving = [cells[i]]
            cells[i] = Self.empty
        case .tableau(let t):
            moving = Array(cols[t].suffix(move.count))
            cols[t].removeLast(move.count)
        case .foundation:
            return
        }
        switch move.to {
        case .cell(let i): cells[i] = moving[0]
        case .foundation(let s): found[s] += UInt8(moving.count)
        case .tableau(let t): cols[t].append(contentsOf: moving)
        }
    }

    /// Candidate moves (foundation plays, column moves sized to fit, cell moves).
    func moves() -> [FreeCell.Move] {
        var result: [FreeCell.Move] = []
        let free = freeCells
        let empties = emptyCols
        let firstEmptyCol = cols.firstIndex(where: \.isEmpty)
        let firstFreeCell = cells.firstIndex(of: Self.empty)
        let maxToCards = (free + 1) << empties
        let maxToEmpty = (free + 1) << max(0, empties - 1)

        // To foundations.
        for i in 0..<cells.count where cells[i] != Self.empty && canFound(cells[i]) {
            result.append(.init(from: .cell(i), to: .foundation(Self.suit(cells[i]))))
        }
        for t in 0..<cols.count {
            if let c = cols[t].last, canFound(c) { result.append(.init(from: .tableau(t), to: .foundation(Self.suit(c)))) }
        }
        // Column to column.
        for s in 0..<cols.count where !cols[s].isEmpty {
            let run = runLength(s)
            let col = cols[s]
            for t in 0..<cols.count where t != s {
                if let top = cols[t].last {
                    let topRank = Self.rank(top)
                    let k = topRank - 1 - Self.rank(col[col.count - 1]) + 1
                    guard k >= 1, k <= run, k <= maxToCards else { continue }
                    if Self.stacks(col[col.count - k], on: top) {
                        result.append(.init(from: .tableau(s), to: .tableau(t), count: k))
                    }
                } else if t == firstEmptyCol {
                    let k = min(run, maxToEmpty)
                    if k < col.count { result.append(.init(from: .tableau(s), to: .tableau(t), count: k)) }
                    if k > 1 && col.count > 1 { result.append(.init(from: .tableau(s), to: .tableau(t), count: 1)) }
                }
            }
        }
        // Cell to column.
        for i in 0..<cells.count where cells[i] != Self.empty {
            let c = cells[i]
            for t in 0..<cols.count {
                if let top = cols[t].last {
                    if Self.stacks(c, on: top) { result.append(.init(from: .cell(i), to: .tableau(t))) }
                } else if t == firstEmptyCol {
                    result.append(.init(from: .cell(i), to: .tableau(t)))
                }
            }
        }
        // Column to cell.
        if let cell = firstFreeCell {
            for t in 0..<cols.count where !cols[t].isEmpty {
                result.append(.init(from: .tableau(t), to: .cell(cell)))
            }
        }
        return result
    }

    /// Lower is closer to a win.
    var heuristic: Int {
        var remaining = 52
        for f in found { remaining -= Int(f) }
        var blocking = 0
        var depthOfNext = 0
        for col in cols {
            var minBelow = 99
            for (i, c) in col.enumerated() {
                let r = Self.rank(c)
                if r > minBelow { blocking += 1 }
                minBelow = min(minBelow, r)
                if canFound(c) { depthOfNext += col.count - 1 - i }
            }
        }
        let used = cells.count - freeCells
        return remaining * 5 + blocking * 5 + depthOfNext * 3 + used * 2 - emptyCols * 8
    }

    /// Identifies a position regardless of free-cell order and column order.
    var key: UInt64 {
        var colHashes = cols.map { col -> UInt64 in
            var h: UInt64 = 0xCBF2_9CE4_8422_2325
            for c in col { h = (h ^ UInt64(c)) &* 0x100_0000_01B3 }
            return (h ^ UInt64(col.count)) &* 0x100_0000_01B3
        }
        colHashes.sort()
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        for c in colHashes { h = (h ^ c) &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 29 }
        for c in cells.sorted() { h = (h ^ UInt64(c)) &* 0x94D0_49BB_1331_11EB; h ^= h >> 31 }
        for f in found { h = (h ^ UInt64(f)) &* 0x100_0000_01B3 }
        return h
    }
}

/// A small binary min-heap.
struct FreeCellHeap<Element: Comparable> {
    private var items: [Element] = []
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    mutating func push(_ e: Element) {
        items.append(e)
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard items[i] < items[p] else { break }
            items.swapAt(i, p)
            i = p
        }
    }

    mutating func pop() -> Element? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count, items[l] < items[m] { m = l }
            if r < items.count, items[r] < items[m] { m = r }
            if m == i { break }
            items.swapAt(i, m)
            i = m
        }
        return top
    }
}
