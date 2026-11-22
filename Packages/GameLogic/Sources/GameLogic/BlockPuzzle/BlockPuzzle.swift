/// Block Puzzle: drop polyomino pieces onto an 8×8 board. Completely filled rows *and*
/// columns clear at the same time. The game ends when no piece in the tray fits anywhere.
public enum BlockPuzzle {
    public static let size = 8
    public static let traySize = 3
    /// Number of distinct block colors pieces can have (indices `0..<colorCount`).
    public static let colorCount = 8

    // MARK: - Shapes

    /// One orientation of a polyomino in the catalog.
    public struct Shape: Hashable, Sendable {
        public let family: String
        /// Normalized cells (top-left of bounding box at 0,0), sorted row-major.
        public let cells: [GridPoint]
        /// Relative draw frequency of this orientation.
        public let weight: Double
        public let color: Int

        public var width: Int { (cells.map(\.col).max() ?? 0) + 1 }
        public var height: Int { (cells.map(\.row).max() ?? 0) + 1 }
    }

    /// Every orientation the generator can deal, with weights that favor mid-sized pieces.
    public static let shapes: [Shape] = {
        var all: [Shape] = []
        func add(_ family: String, _ rows: [String], weight: Double, color: Int, rotate: Bool = true) {
            let base = parse(rows)
            var orientations: [[GridPoint]] = [base]
            if rotate {
                var current = base
                for _ in 0..<3 {
                    current = normalize(current.map { GridPoint(row: $0.col, col: -$0.row) })
                    if !orientations.contains(current) { orientations.append(current) }
                }
            }
            let each = weight / Double(orientations.count)
            for cells in orientations {
                all.append(Shape(family: family, cells: cells, weight: each, color: color))
            }
        }
        // Color indices: 0 cherry, 1 tangerine, 2 lemon, 3 lime, 4 aqua, 5 sky, 6 grape, 7 bubblegum.
        add("dot", ["#"], weight: 3, color: 7)
        add("domino", ["##"], weight: 6, color: 2)
        add("line3", ["###"], weight: 8, color: 1)
        add("corner3", ["#.", "##"], weight: 9, color: 3)
        add("line4", ["####"], weight: 7, color: 4)
        add("square2", ["##", "##"], weight: 8, color: 2)
        add("L", ["#.", "#.", "##"], weight: 7, color: 5)
        add("J", [".#", ".#", "##"], weight: 7, color: 1)
        add("T", ["###", ".#."], weight: 8, color: 6)
        add("S", [".##", "##."], weight: 5, color: 3)
        add("Z", ["##.", ".##"], weight: 5, color: 0)
        add("line5", ["#####"], weight: 4, color: 0)
        add("corner5", ["#..", "#..", "###"], weight: 5, color: 4)
        add("rect", ["###", "###"], weight: 5, color: 6)
        add("square3", ["###", "###", "###"], weight: 3, color: 5)
        return all
    }()

    /// Parses rows like `["#.", "##"]` into normalized cells.
    public static func parse(_ rows: [String]) -> [GridPoint] {
        var cells: [GridPoint] = []
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" {
                cells.append(GridPoint(row: r, col: c))
            }
        }
        return normalize(cells)
    }

    static func normalize(_ cells: [GridPoint]) -> [GridPoint] {
        let minRow = cells.map(\.row).min() ?? 0
        let minCol = cells.map(\.col).min() ?? 0
        return cells.map { GridPoint(row: $0.row - minRow, col: $0.col - minCol) }
            .sorted { ($0.row, $0.col) < ($1.row, $1.col) }
    }

    // MARK: - Pieces

    public struct Piece: Identifiable, Hashable, Codable, Sendable {
        public let id: Int
        public let family: String
        /// Normalized cells relative to the piece's top-left corner.
        public let cells: [GridPoint]
        public let color: Int

        public init(id: Int, family: String, cells: [GridPoint], color: Int) {
            self.id = id
            self.family = family
            self.cells = BlockPuzzle.normalize(cells)
            self.color = color
        }

        public init(id: Int, shape: Shape) {
            self.init(id: id, family: shape.family, cells: shape.cells, color: shape.color)
        }

        /// Convenience for tests: `Piece(id: 0, rows: ["##", "#."])`.
        public init(id: Int, rows: [String], color: Int = 0) {
            self.init(id: id, family: "custom", cells: BlockPuzzle.parse(rows), color: color)
        }

        public var width: Int { (cells.map(\.col).max() ?? 0) + 1 }
        public var height: Int { (cells.map(\.row).max() ?? 0) + 1 }

        /// Absolute cells when the piece's top-left corner sits at `origin`.
        public func cells(at origin: GridPoint) -> [GridPoint] {
            cells.map { $0 + origin }
        }

        /// The origin that puts the piece's bounding-box center as close as possible to `cell`.
        public func origin(centeredOn cell: GridPoint) -> GridPoint {
            GridPoint(row: cell.row - (height - 1) / 2, col: cell.col - (width - 1) / 2)
        }
    }

    // MARK: - Board

    public struct Board: Hashable, Codable, Sendable {
        /// Row-major color indices; `nil` = empty.
        public private(set) var cells: [Int?]

        public init() {
            cells = Array(repeating: nil, count: size * size)
        }

        /// Test helper: rows of `.` (empty) or a digit color / `#` (color 0).
        public init(rows: [String]) {
            self.init()
            for (r, line) in rows.enumerated() {
                for (c, ch) in line.enumerated() where ch != "." {
                    self[GridPoint(row: r, col: c)] = ch.wholeNumberValue ?? 0
                }
            }
        }

        public subscript(point: GridPoint) -> Int? {
            get { cells[point.row * size + point.col] }
            set { cells[point.row * size + point.col] = newValue }
        }

        public var filledCount: Int { cells.lazy.filter { $0 != nil }.count }
        public var isEmpty: Bool { cells.allSatisfy { $0 == nil } }

        public func fits(_ piece: Piece, at origin: GridPoint) -> Bool {
            for cell in piece.cells {
                let p = cell + origin
                guard p.isInside(rows: size, cols: size), self[p] == nil else { return false }
            }
            return true
        }

        /// Every origin where the piece can be placed.
        public func validOrigins(for piece: Piece) -> [GridPoint] {
            var result: [GridPoint] = []
            for r in 0...(size - piece.height) {
                for c in 0...(size - piece.width) {
                    let o = GridPoint(row: r, col: c)
                    if fits(piece, at: o) { result.append(o) }
                }
            }
            return result
        }

        public func fitsAnywhere(_ piece: Piece) -> Bool {
            guard piece.width <= size, piece.height <= size else { return false }
            for r in 0...(size - piece.height) {
                for c in 0...(size - piece.width) where fits(piece, at: GridPoint(row: r, col: c)) {
                    return true
                }
            }
            return false
        }

        public func isRowFull(_ row: Int) -> Bool {
            (0..<size).allSatisfy { self[GridPoint(row: row, col: $0)] != nil }
        }

        public func isColumnFull(_ col: Int) -> Bool {
            (0..<size).allSatisfy { self[GridPoint(row: $0, col: col)] != nil }
        }

        /// Rows and columns that would be complete after dropping `piece` at `origin`.
        /// Returns `nil` if the piece doesn't fit there.
        public func linesCompleted(by piece: Piece, at origin: GridPoint) -> (rows: [Int], cols: [Int])? {
            guard fits(piece, at: origin) else { return nil }
            var copy = self
            for p in piece.cells(at: origin) { copy[p] = piece.color }
            return (copy.fullRows, copy.fullColumns)
        }

        public var fullRows: [Int] { (0..<size).filter(isRowFull) }
        public var fullColumns: [Int] { (0..<size).filter(isColumnFull) }

        /// The valid origin closest to a fractional board position (in cells), within `maxDistance`.
        public func nearestValidOrigin(for piece: Piece, row: Double, col: Double,
                                       maxDistance: Double = 1.0) -> GridPoint? {
            var best: (GridPoint, Double)?
            let minR = max(0, Int((row - maxDistance).rounded(.down)))
            let maxR = min(size - piece.height, Int((row + maxDistance).rounded(.up)))
            let minC = max(0, Int((col - maxDistance).rounded(.down)))
            let maxC = min(size - piece.width, Int((col + maxDistance).rounded(.up)))
            guard minR <= maxR, minC <= maxC else { return nil }
            for r in minR...maxR {
                for c in minC...maxC {
                    let o = GridPoint(row: r, col: c)
                    let d = ((Double(r) - row) * (Double(r) - row) + (Double(c) - col) * (Double(c) - col)).squareRoot()
                    guard d <= maxDistance, fits(piece, at: o) else { continue }
                    if best == nil || d < best!.1 { best = (o, d) }
                }
            }
            return best?.0
        }
    }

    // MARK: - Scoring

    public struct ClearedCell: Hashable, Sendable {
        public let point: GridPoint
        public let color: Int
    }

    /// Everything the UI needs to animate a placement.
    public struct Placement: Equatable, Sendable {
        public var slot: Int
        public var piece: Piece
        public var origin: GridPoint
        public var placedCells: [GridPoint]
        public var clearedRows: [Int]
        public var clearedColumns: [Int]
        /// Cells removed by the clear, with the color they had.
        public var clearedCells: [ClearedCell]
        public var points: Int
        /// Consecutive clearing placements including this one (0 if nothing cleared).
        public var streak: Int
        public var isPerfectClear: Bool
        /// The tray was emptied and dealt three new pieces.
        public var refilled: Bool

        public var lineCount: Int { clearedRows.count + clearedColumns.count }
    }

    public static let perfectClearBonus = 300

    /// Points for one placement.
    /// - cells: blocks placed (1 point each).
    /// - lines: lines cleared at once; `10 × lines²` rewards combos (1→10, 2→40, 3→90…).
    /// - streak: consecutive clearing placements; each step beyond the first adds `10 × lines`.
    public static func points(cells: Int, lines: Int, streak: Int, perfectClear: Bool = false) -> Int {
        guard lines > 0 else { return cells }
        let combo = 10 * lines * lines
        let streakBonus = 10 * lines * max(0, streak - 1)
        return cells + combo + streakBonus + (perfectClear ? perfectClearBonus : 0)
    }

    // MARK: - State

    public struct State: Codable, Equatable, Sendable {
        public private(set) var board: Board
        /// Three slots; `nil` once that piece has been placed.
        public private(set) var tray: [Piece?]
        public private(set) var score: Int
        public private(set) var streak: Int
        public private(set) var linesCleared: Int
        public private(set) var piecesPlaced: Int
        private var nextID: Int
        private var rng: SeededRandom

        public static func newGame(seed: UInt64 = .random(in: .min ... .max)) -> State {
            var s = State(board: Board(), tray: [], seed: seed)
            s.refillTray()
            return s
        }

        /// Creates a state from an explicit board and tray (tests). An empty tray is dealt.
        public init(board: Board, tray: [Piece?], seed: UInt64, score: Int = 0, streak: Int = 0) {
            self.board = board
            self.tray = tray
            self.score = score
            self.streak = streak
            self.linesCleared = 0
            self.piecesPlaced = 0
            self.nextID = (tray.compactMap { $0?.id }.max() ?? -1) + 1
            self.rng = SeededRandom(seed: seed)
            if tray.allSatisfy({ $0 == nil }) { refillTray() }
        }

        public var remainingPieces: [Piece] { tray.compactMap { $0 } }

        /// No piece left in the tray fits anywhere on the board.
        public var isOver: Bool {
            let pieces = remainingPieces
            return !pieces.isEmpty && !pieces.contains { board.fitsAnywhere($0) }
        }

        public func canPlace(slot: Int, at origin: GridPoint) -> Bool {
            guard tray.indices.contains(slot), let piece = tray[slot] else { return false }
            return board.fits(piece, at: origin)
        }

        public func canPlaceAnywhere(slot: Int) -> Bool {
            guard tray.indices.contains(slot), let piece = tray[slot] else { return false }
            return board.fitsAnywhere(piece)
        }

        /// Places the piece in `slot` with its top-left corner at `origin`.
        /// Returns `nil` (and changes nothing) if the move is invalid.
        @discardableResult
        public mutating func place(slot: Int, at origin: GridPoint) -> Placement? {
            guard tray.indices.contains(slot), let piece = tray[slot], board.fits(piece, at: origin) else {
                return nil
            }
            let placed = piece.cells(at: origin)
            for p in placed { board[p] = piece.color }

            let rows = board.fullRows
            let cols = board.fullColumns
            var cleared: [ClearedCell] = []
            var seen = Set<GridPoint>()
            for r in rows {
                for c in 0..<size { seen.insert(GridPoint(row: r, col: c)) }
            }
            for c in cols {
                for r in 0..<size { seen.insert(GridPoint(row: r, col: c)) }
            }
            for p in seen.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                if let color = board[p] { cleared.append(ClearedCell(point: p, color: color)) }
                board[p] = nil
            }

            let lines = rows.count + cols.count
            streak = lines > 0 ? streak + 1 : 0
            let perfect = lines > 0 && board.isEmpty
            let gained = BlockPuzzle.points(cells: placed.count, lines: lines, streak: streak, perfectClear: perfect)
            score += gained
            linesCleared += lines
            piecesPlaced += 1

            tray[slot] = nil
            var refilled = false
            if tray.allSatisfy({ $0 == nil }) {
                refillTray()
                refilled = true
            }
            return Placement(slot: slot, piece: piece, origin: origin, placedCells: placed,
                             clearedRows: rows, clearedColumns: cols, clearedCells: cleared,
                             points: gained, streak: streak, isPerfectClear: perfect, refilled: refilled)
        }

        // MARK: Generation

        private static let totalWeight = shapes.reduce(0) { $0 + $1.weight }

        private mutating func drawShape(from pool: [Shape], total: Double) -> Shape {
            var roll = Double.random(in: 0..<total, using: &rng)
            for shape in pool {
                roll -= shape.weight
                if roll < 0 { return shape }
            }
            return pool[pool.count - 1]
        }

        private mutating func makePiece(_ shape: Shape) -> Piece {
            defer { nextID += 1 }
            return Piece(id: nextID, shape: shape)
        }

        /// Deals three new pieces. Draws are weighted; deals where nothing fits are re-rolled
        /// a few times, and as a last resort one slot is drawn only from shapes that fit.
        /// Because a completely full board is impossible (full lines clear), a dot always fits,
        /// so every fresh tray contains at least one playable piece.
        mutating func refillTray() {
            for _ in 0..<12 {
                let candidate = (0..<traySize).map { _ in drawShape(from: shapes, total: Self.totalWeight) }
                if candidate.contains(where: { board.fitsAnywhere(Piece(id: 0, shape: $0)) }) {
                    tray = candidate.map { makePiece($0) }
                    return
                }
            }
            let fitting = shapes.filter { board.fitsAnywhere(Piece(id: 0, shape: $0)) }
            var dealt = (0..<traySize).map { _ in drawShape(from: shapes, total: Self.totalWeight) }
            if !fitting.isEmpty {
                let slot = Int.random(in: 0..<traySize, using: &rng)
                dealt[slot] = drawShape(from: fitting, total: fitting.reduce(0) { $0 + $1.weight })
            }
            tray = dealt.map { makePiece($0) }
        }
    }
}
