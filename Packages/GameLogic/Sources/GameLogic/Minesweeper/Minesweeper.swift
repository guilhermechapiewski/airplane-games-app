/// Minesweeper: uncover every safe cell of a field without touching a mine.
///
/// Mines are placed lazily on the first reveal so the first tap is always safe and
/// opens an area (the tapped cell and its neighbours are kept mine-free).
public enum Minesweeper {
    public enum Level: String, CaseIterable, Codable, Sendable, Identifiable {
        case beginner, intermediate, expert

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .beginner: "Beginner"
            case .intermediate: "Intermediate"
            case .expert: "Expert"
            }
        }

        /// Expert is laid out in portrait (tall) orientation for phones.
        public var rows: Int {
            switch self {
            case .beginner: 9
            case .intermediate: 16
            case .expert: 30
            }
        }

        public var cols: Int {
            switch self {
            case .beginner: 9
            case .intermediate: 16
            case .expert: 16
            }
        }

        public var mines: Int {
            switch self {
            case .beginner: 10
            case .intermediate: 40
            case .expert: 99
            }
        }
    }

    public enum Mark: String, Codable, Sendable {
        case hidden, flagged, revealed
    }

    public struct Cell: Codable, Equatable, Hashable, Sendable {
        public var isMine = false
        /// Number of mines in the 8 surrounding cells.
        public var adjacent = 0
        public var mark: Mark = .hidden

        public var isRevealed: Bool { mark == .revealed }
        public var isFlagged: Bool { mark == .flagged }
    }

    public enum Status: String, Codable, Sendable {
        /// No mines placed yet; waiting for the first reveal.
        case ready
        case playing
        case won
        case lost

        public var isOver: Bool { self == .won || self == .lost }
    }

    /// What a reveal or chord did, for animation and feedback.
    public struct Outcome: Equatable, Sendable {
        /// Newly revealed cells, in flood-fill (distance) order.
        public var revealed: [GridPoint] = []
        /// The mine that was set off, if any.
        public var exploded: GridPoint?

        public var isEmpty: Bool { revealed.isEmpty && exploded == nil }
    }

    public struct State: Codable, Equatable, Sendable {
        public let rows: Int
        public let cols: Int
        public let mineCount: Int
        public private(set) var cells: [Cell]
        public private(set) var status: Status = .ready
        /// The mine that ended the game.
        public private(set) var exploded: GridPoint?
        public private(set) var revealedCount = 0
        private var rng: SeededRandom

        public init(level: Level, seed: UInt64 = .random(in: .min ... .max)) {
            self.init(rows: level.rows, cols: level.cols, mines: level.mines, seed: seed)
        }

        public init(rows: Int, cols: Int, mines: Int, seed: UInt64 = .random(in: .min ... .max)) {
            precondition(rows > 0 && cols > 0, "Board must not be empty")
            precondition(mines >= 0 && mines < rows * cols, "Need at least one safe cell")
            self.rows = rows
            self.cols = cols
            self.mineCount = mines
            self.cells = Array(repeating: Cell(), count: rows * cols)
            self.rng = SeededRandom(seed: seed)
        }

        /// A board with mines at fixed positions (already "playing"). Useful for tests.
        public init(rows: Int, cols: Int, mines: Set<GridPoint>) {
            self.init(rows: rows, cols: cols, mines: mines.count, seed: 0)
            placeMines(at: mines)
            status = .playing
        }

        // MARK: Queries

        public subscript(_ p: GridPoint) -> Cell { cells[index(p)] }

        public var hasMines: Bool { status != .ready }
        public var safeCellCount: Int { rows * cols - mineCount }
        public var flagCount: Int { cells.reduce(0) { $0 + ($1.isFlagged ? 1 : 0) } }
        /// Mines minus flags; may go negative if the player over-flags.
        public var minesLeft: Int { mineCount - flagCount }

        public var allPoints: [GridPoint] {
            (0..<rows).flatMap { r in (0..<cols).map { GridPoint(row: r, col: $0) } }
        }

        public var minePoints: [GridPoint] { allPoints.filter { self[$0].isMine } }

        /// Flags placed on cells that are not mines (only meaningful once mines exist).
        public var wrongFlags: [GridPoint] { allPoints.filter { self[$0].isFlagged && !self[$0].isMine } }

        public func neighbors(of p: GridPoint) -> [GridPoint] {
            GridPoint.neighborOffsets.map { p + $0 }.filter { $0.isInside(rows: rows, cols: cols) }
        }

        public func contains(_ p: GridPoint) -> Bool { p.isInside(rows: rows, cols: cols) }

        /// Whether tapping a revealed number would reveal anything (flags match and hidden neighbours exist).
        public func canChord(at p: GridPoint) -> Bool {
            guard contains(p), status == .playing else { return false }
            let cell = self[p]
            guard cell.isRevealed, cell.adjacent > 0 else { return false }
            let around = neighbors(of: p)
            let flags = around.filter { self[$0].isFlagged }.count
            return flags == cell.adjacent && around.contains { self[$0].mark == .hidden }
        }

        // MARK: Actions

        /// Reveals a hidden cell. Places mines on the very first reveal.
        @discardableResult
        public mutating func reveal(_ p: GridPoint) -> Outcome {
            guard contains(p), !status.isOver, self[p].mark == .hidden else { return Outcome() }
            if status == .ready {
                generate(safeAround: p)
                status = .playing
            }
            var outcome = Outcome()
            open(p, into: &outcome)
            settle(&outcome)
            return outcome
        }

        /// Reveals all un-flagged neighbours of a satisfied number.
        @discardableResult
        public mutating func chord(_ p: GridPoint) -> Outcome {
            guard canChord(at: p) else { return Outcome() }
            var outcome = Outcome()
            for n in neighbors(of: p) where self[n].mark == .hidden {
                open(n, into: &outcome)
            }
            settle(&outcome)
            return outcome
        }

        /// Toggles a flag on a hidden cell. Returns whether anything changed.
        @discardableResult
        public mutating func toggleFlag(_ p: GridPoint) -> Bool {
            guard contains(p), !status.isOver else { return false }
            let i = index(p)
            switch cells[i].mark {
            case .hidden: cells[i].mark = .flagged
            case .flagged: cells[i].mark = .hidden
            case .revealed: return false
            }
            return true
        }

        // MARK: Internals

        private func index(_ p: GridPoint) -> Int { p.row * cols + p.col }

        /// Places mines uniformly at random, keeping `safe` and (when room allows) its neighbours clear.
        mutating func generate(safeAround safe: GridPoint) {
            var excluded = Set([safe] + neighbors(of: safe))
            if rows * cols - excluded.count < mineCount { excluded = [safe] }
            var candidates = allPoints.filter { !excluded.contains($0) }
            candidates.shuffle(using: &rng)
            placeMines(at: Set(candidates.prefix(mineCount)))
        }

        private mutating func placeMines(at mines: Set<GridPoint>) {
            for p in mines { cells[index(p)].isMine = true }
            for p in allPoints {
                cells[index(p)].adjacent = neighbors(of: p).filter { mines.contains($0) }.count
            }
        }

        /// Breadth-first flood fill from `start`, opening zeros' neighbours.
        private mutating func open(_ start: GridPoint, into outcome: inout Outcome) {
            guard self[start].mark == .hidden else { return }
            if self[start].isMine {
                cells[index(start)].mark = .revealed
                if outcome.exploded == nil { outcome.exploded = start }
                return
            }
            var queue = [start]
            var head = 0
            cells[index(start)].mark = .revealed
            while head < queue.count {
                let p = queue[head]
                head += 1
                outcome.revealed.append(p)
                revealedCount += 1
                guard self[p].adjacent == 0 else { continue }
                for n in neighbors(of: p) where self[n].mark == .hidden && !self[n].isMine {
                    cells[index(n)].mark = .revealed
                    queue.append(n)
                }
            }
        }

        private mutating func settle(_ outcome: inout Outcome) {
            if let boom = outcome.exploded {
                status = .lost
                exploded = boom
            } else if revealedCount == safeCellCount {
                status = .won
                // Winning flags every remaining mine.
                for i in cells.indices where cells[i].isMine { cells[i].mark = .flagged }
            }
        }
    }
}
