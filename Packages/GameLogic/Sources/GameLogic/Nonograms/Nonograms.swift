/// Nonograms: fill grid cells so every row and column matches its run-length clue,
/// revealing a hidden picture.
public enum Nonograms {
    // MARK: Sizes

    public enum Size: String, CaseIterable, Codable, Sendable, Identifiable {
        case easy, medium, hard

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .easy: "Easy"
            case .medium: "Medium"
            case .hard: "Hard"
            }
        }

        public var dimension: Int {
            switch self {
            case .easy: 5
            case .medium: 10
            case .hard: 15
            }
        }

        public init?(dimension: Int) {
            guard let match = Size.allCases.first(where: { $0.dimension == dimension }) else { return nil }
            self = match
        }
    }

    // MARK: Puzzle

    /// A picture puzzle defined by its solution bitmap.
    public struct Puzzle: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        /// The color the picture is revealed in (0xRRGGBB).
        public let color: UInt32
        public let width: Int
        public let height: Int
        /// Row-major solution; `true` = filled.
        public let solution: [Bool]
        public let rowClues: [[Int]]
        public let columnClues: [[Int]]

        /// Creates a puzzle from rows of `#` (filled) and `.` (empty).
        public init(id: String, title: String, color: UInt32, art: [String]) {
            let rows = art.map { $0.map { $0 == "#" } }
            precondition(!rows.isEmpty && Set(rows.map(\.count)).count == 1, "Art for \(id) must be rectangular")
            self.init(id: id, title: title, color: color, rows: rows)
        }

        public init(id: String, title: String, color: UInt32 = 0, rows: [[Bool]]) {
            self.id = id
            self.title = title
            self.color = color
            height = rows.count
            width = rows.first?.count ?? 0
            solution = rows.flatMap { $0 }
            rowClues = rows.map(Nonograms.clue(for:))
            columnClues = (0..<width).map { c in Nonograms.clue(for: rows.map { $0[c] }) }
        }

        public subscript(row: Int, col: Int) -> Bool { solution[row * width + col] }
        public subscript(_ p: GridPoint) -> Bool { self[p.row, p.col] }

        public var size: Size? { width == height ? Size(dimension: width) : nil }
        public var filledCount: Int { solution.filter { $0 }.count }

        public func row(_ r: Int) -> [Bool] { Array(solution[(r * width)..<((r + 1) * width)]) }
        public func column(_ c: Int) -> [Bool] { (0..<height).map { self[$0, c] } }
    }

    /// Run lengths of filled cells in a line. An empty line has the clue `[]`.
    public static func clue(for line: [Bool]) -> [Int] {
        var runs: [Int] = []
        var run = 0
        for filled in line {
            if filled {
                run += 1
            } else if run > 0 {
                runs.append(run)
                run = 0
            }
        }
        if run > 0 { runs.append(run) }
        return runs
    }

    // MARK: Player board

    public enum Mark: Int, Codable, Sendable {
        case empty = 0, filled, crossed
    }

    /// The tool a stroke paints with.
    public enum Tool: String, Codable, Sendable {
        case fill, cross

        var mark: Mark { self == .fill ? .filled : .crossed }
    }

    /// The player's grid of marks.
    public struct Board: Codable, Equatable, Hashable, Sendable {
        public let width: Int
        public let height: Int
        public private(set) var cells: [Mark]

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
            cells = Array(repeating: .empty, count: width * height)
        }

        public init(for puzzle: Puzzle) {
            self.init(width: puzzle.width, height: puzzle.height)
        }

        public subscript(_ p: GridPoint) -> Mark {
            get { cells[p.row * width + p.col] }
            set { cells[p.row * width + p.col] = newValue }
        }

        public subscript(row: Int, col: Int) -> Mark { self[GridPoint(row: row, col: col)] }

        public func contains(_ p: GridPoint) -> Bool { p.isInside(rows: height, cols: width) }

        public var isBlank: Bool { cells.allSatisfy { $0 == .empty } }
        public var filledCount: Int { cells.filter { $0 == .filled }.count }

        public func rowFills(_ r: Int) -> [Bool] { (0..<width).map { self[r, $0] == .filled } }
        public func columnFills(_ c: Int) -> [Bool] { (0..<height).map { self[$0, c] == .filled } }

        /// A line is satisfied when its filled runs exactly match the clue.
        public func isRowSatisfied(_ r: Int, in puzzle: Puzzle) -> Bool {
            Nonograms.clue(for: rowFills(r)) == puzzle.rowClues[r]
        }

        public func isColumnSatisfied(_ c: Int, in puzzle: Puzzle) -> Bool {
            Nonograms.clue(for: columnFills(c)) == puzzle.columnClues[c]
        }

        /// Solved when the filled cells match the picture exactly (crosses are ignored).
        public func isSolved(_ puzzle: Puzzle) -> Bool {
            guard width == puzzle.width, height == puzzle.height else { return false }
            return cells.indices.allSatisfy { (cells[$0] == .filled) == puzzle.solution[$0] }
        }

        /// Cells that contradict the solution: fills on blank cells and crosses on picture cells.
        public func mistakes(in puzzle: Puzzle) -> [GridPoint] {
            allPoints.filter { p in
                switch self[p] {
                case .filled: !puzzle[p]
                case .crossed: puzzle[p]
                case .empty: false
                }
            }
        }

        public var allPoints: [GridPoint] {
            (0..<height).flatMap { r in (0..<width).map { GridPoint(row: r, col: $0) } }
        }

        /// The finished picture: every picture cell filled, the rest crossed.
        public static func solved(_ puzzle: Puzzle) -> Board {
            var b = Board(for: puzzle)
            b.cells = puzzle.solution.map { $0 ? .filled : .crossed }
            return b
        }

        // MARK: Strokes

        /// Applies a stroke from `start` to `end` (locked to the start's row or column).
        /// Returns the cells that changed.
        @discardableResult
        public mutating func apply(_ stroke: Stroke, to end: GridPoint) -> [GridPoint] {
            var changed: [GridPoint] = []
            for p in stroke.cells(to: end) where contains(p) {
                let current = self[p]
                guard let next = stroke.action.result(for: current), next != current else { continue }
                self[p] = next
                changed.append(p)
            }
            return changed
        }

        /// A hint: a cell whose correct mark can be deduced from the player's correct marks
        /// with a single line-solving step, preferring to fix mistakes first.
        public func hint(for puzzle: Puzzle) -> (point: GridPoint, mark: Mark)? {
            explainedHint(for: puzzle).map { ($0.point, $0.mark) }
        }

        /// The next hint with its reasoning: a mistake to fix, or a cell that one row or column
        /// decides (given the player's correct marks), preferring picture cells.
        public func explainedHint(for puzzle: Puzzle) -> Hint? {
            if let wrong = mistakes(in: puzzle).first {
                return Hint(kind: .mistake, point: wrong, mark: puzzle[wrong] ? .filled : .crossed, line: nil,
                            title: "Check This Square",
                            explanation: "This square is marked wrong: it doesn't match the picture.")
            }
            // What the player has established (only correct marks count; there are none wrong here).
            let known: [[Solver.Cell]] = (0..<height).map { r in
                (0..<width).map { c in
                    switch self[r, c] {
                    case .filled: .filled
                    case .crossed: .empty
                    case .empty: .unknown
                    }
                }
            }
            func correctMark(_ p: GridPoint) -> Mark { puzzle[p] ? .filled : .crossed }
            var candidates: [(point: GridPoint, line: Line)] = []
            for r in 0..<height {
                if let solved = Solver.solveLine(clue: puzzle.rowClues[r], line: known[r]) {
                    for c in 0..<width where known[r][c] == .unknown && solved[c] != .unknown {
                        candidates.append((GridPoint(row: r, col: c), .row(r)))
                    }
                }
            }
            for c in 0..<width {
                let column = (0..<height).map { known[$0][c] }
                if let solved = Solver.solveLine(clue: puzzle.columnClues[c], line: column) {
                    for r in 0..<height where column[r] == .unknown && solved[r] != .unknown {
                        candidates.append((GridPoint(row: r, col: c), .column(c)))
                    }
                }
            }
            // Prefer revealing a picture cell; it's the more helpful kind of hint.
            if let pick = candidates.first(where: { puzzle[$0.point] }) ?? candidates.first {
                let line = pick.line
                let clue = line.clue(in: puzzle)
                let cells = line.cells(width: width, height: height)
                // Would the clue decide this cell on an empty line? If not, earlier marks matter.
                let blank = [Solver.Cell](repeating: .unknown, count: cells.count)
                let position = cells.firstIndex(of: pick.point)!
                let onItsOwn = Solver.solveLine(clue: clue, line: blank)?[position] != .unknown
                let mark = correctMark(pick.point)
                return Hint(kind: .deduction, point: pick.point, mark: mark, line: line, title: line.title,
                            explanation: Hint.explain(line: line, clue: clue, filled: mark == .filled,
                                                      needsMarks: !onItsOwn))
            }
            // Fallback (e.g. the player has crossed cells that aren't needed): any unmarked picture cell.
            let fallback = allPoints.first(where: { self[$0] == .empty && puzzle[$0] }).map { ($0, Mark.filled) }
                ?? allPoints.first(where: { self[$0] == .empty && !puzzle[$0] }).map { ($0, Mark.crossed) }
            return fallback.map { point, mark in
                Hint(kind: .reveal, point: point, mark: mark, line: nil, title: "Answer",
                     explanation: "No single row or column decides a square right now, so this hint just shows "
                        + "one from the picture.")
            }
        }
    }

    /// A row or column of the board.
    public enum Line: Hashable, Sendable {
        case row(Int)
        case column(Int)

        public func cells(width: Int, height: Int) -> [GridPoint] {
            switch self {
            case .row(let r): (0..<width).map { GridPoint(row: r, col: $0) }
            case .column(let c): (0..<height).map { GridPoint(row: $0, col: c) }
            }
        }

        public func clue(in puzzle: Puzzle) -> [Int] {
            switch self {
            case .row(let r): puzzle.rowClues[r]
            case .column(let c): puzzle.columnClues[c]
            }
        }

        /// "Row 3" or "Column 5" (1-based, as players count).
        public var title: String {
            switch self {
            case .row(let r): "Row \(r + 1)"
            case .column(let c): "Column \(c + 1)"
            }
        }

        var noun: String {
            switch self {
            case .row: "row"
            case .column: "column"
            }
        }
    }

    /// A hint, explained: which square, its correct mark, and why.
    public struct Hint: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// One row or column decides the square.
            case deduction
            /// The square is marked wrong; the answer corrects it.
            case mistake
            /// Nothing single-line decides a square; the answer is simply shown.
            case reveal
        }

        public let kind: Kind
        public let point: GridPoint
        public let mark: Mark
        /// The row or column that decides it (deductions only).
        public let line: Line?
        public let title: String
        public let explanation: String

        static func explain(line: Line, clue: [Int], filled: Bool, needsMarks: Bool) -> String {
            let noun = line.noun
            let given = needsMarks ? ", given the squares already marked," : ""
            if clue.isEmpty || clue == [0] {
                return "\(line.title)'s clue is 0: nothing in this \(noun) is filled, so this square stays empty."
            }
            let clueText = clue.map(String.init).joined(separator: " ")
            let blocks = clue.count == 1 ? "that block" : "those blocks"
            return filled
                ? "\(line.title)'s clue is \(clueText). Every way \(blocks) can fit in this \(noun)\(given) covers this square, so it's filled."
                : "\(line.title)'s clue is \(clueText). No way \(blocks) can fit in this \(noun)\(given) reaches this square, so it stays empty."
        }
    }

    /// A drag across the board. Its effect is decided by the tool and the cell where it began.
    public struct Stroke: Codable, Equatable, Sendable {
        public enum Action: Codable, Equatable, Sendable {
            /// Paint `mark` on empty cells.
            case paint(Mark)
            /// Replace `from` (and empty cells) with `to`.
            case overwrite(from: Mark, to: Mark)
            /// Clear cells that have `mark`.
            case erase(Mark)

            func result(for current: Mark) -> Mark? {
                switch self {
                case .paint(let m): current == .empty ? m : nil
                case .overwrite(let from, let to): (current == from || current == .empty) ? to : nil
                case .erase(let m): current == m ? .empty : nil
                }
            }
        }

        public let start: GridPoint
        public let action: Action

        public init(tool: Tool, start: GridPoint, startingMark: Mark) {
            self.start = start
            let target = tool.mark
            if startingMark == target {
                action = .erase(target)
            } else if startingMark == .empty {
                action = .paint(target)
            } else {
                action = .overwrite(from: startingMark, to: target)
            }
        }

        /// The straight run of cells from the start toward `end`, along whichever axis moved more.
        public func cells(to end: GridPoint) -> [GridPoint] {
            let dr = end.row - start.row, dc = end.col - start.col
            if abs(dc) >= abs(dr) {
                let step = dc >= 0 ? 1 : -1
                return stride(from: 0, through: abs(dc), by: 1).map { GridPoint(row: start.row, col: start.col + $0 * step) }
            } else {
                let step = dr >= 0 ? 1 : -1
                return stride(from: 0, through: abs(dr), by: 1).map { GridPoint(row: start.row + $0 * step, col: start.col) }
            }
        }
    }
}
