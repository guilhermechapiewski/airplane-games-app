/// Dots and Boxes: players take turns joining two adjacent dots. Drawing the fourth side of a
/// box claims it and earns another move. Whoever claims the most boxes wins.
public enum DotsAndBoxes {
    public enum Player: Int, Codable, Sendable, CaseIterable {
        case one, two

        public var other: Player { self == .one ? .two : .one }
    }

    public enum Orientation: String, Codable, Sendable {
        case horizontal, vertical
    }

    /// A line between two adjacent dots. Dots are addressed by (row, col), 0-based.
    /// A horizontal line joins dot (row, col) to (row, col + 1); a vertical line joins
    /// dot (row, col) to (row + 1, col).
    public struct Line: Hashable, Codable, Sendable, CustomStringConvertible {
        public var orientation: Orientation
        public var row: Int
        public var col: Int

        public init(_ orientation: Orientation, row: Int, col: Int) {
            self.orientation = orientation
            self.row = row
            self.col = col
        }

        public static func h(_ row: Int, _ col: Int) -> Line { Line(.horizontal, row: row, col: col) }
        public static func v(_ row: Int, _ col: Int) -> Line { Line(.vertical, row: row, col: col) }

        /// The two dots this line joins.
        public var dots: (GridPoint, GridPoint) {
            let a = GridPoint(row: row, col: col)
            let b = orientation == .horizontal ? GridPoint(row: row, col: col + 1) : GridPoint(row: row + 1, col: col)
            return (a, b)
        }

        public var description: String { "\(orientation == .horizontal ? "h" : "v")(\(row),\(col))" }
    }

    /// One move: the line drawn, who drew it, and the boxes it completed (0, 1 or 2).
    public struct Turn: Codable, Equatable, Sendable {
        public let line: Line
        public let player: Player
        public let claimed: [GridPoint]
    }
}

extension DotsAndBoxes {
    /// The full game state: board, claimed boxes, whose turn and the move history.
    public struct Game: Codable, Equatable, Sendable {
        /// Number of boxes vertically and horizontally.
        public let rows: Int
        public let cols: Int
        public let firstPlayer: Player
        public private(set) var drawn: [Bool]
        /// Who drew each line (nil for undrawn lines and lines placed by a setup position).
        public private(set) var lineOwners: [Player?]
        /// Box owners, row-major.
        public private(set) var boxOwners: [Player?]
        public private(set) var current: Player
        public private(set) var history: [Turn]

        public init(rows: Int, cols: Int, firstPlayer: Player = .one) {
            precondition(rows >= 1 && cols >= 1 && Self.edgeCount(rows: rows, cols: cols) <= 128,
                         "Board must have between 1 and 128 lines")
            self.rows = rows
            self.cols = cols
            self.firstPlayer = firstPlayer
            let edges = Self.edgeCount(rows: rows, cols: cols)
            drawn = Array(repeating: false, count: edges)
            lineOwners = Array(repeating: nil, count: edges)
            boxOwners = Array(repeating: nil, count: rows * cols)
            current = firstPlayer
            history = []
        }

        /// A position with some lines already drawn (no box may be complete), `current` to move.
        public init(rows: Int, cols: Int, drawn lines: [Line], current: Player = .one) {
            self.init(rows: rows, cols: cols, firstPlayer: current)
            for line in lines {
                precondition(contains(line), "Line \(line) is off the board")
                drawn[index(of: line)] = true
            }
            precondition((0..<rows * cols).allSatisfy { sides(ofBox: $0) < 4 }, "Setup lines must not complete a box")
        }

        // MARK: Geometry

        public static func edgeCount(rows: Int, cols: Int) -> Int {
            (rows + 1) * cols + rows * (cols + 1)
        }

        public var edgeCount: Int { drawn.count }
        public var boxCount: Int { rows * cols }
        private var horizontalCount: Int { (rows + 1) * cols }

        public func contains(_ line: Line) -> Bool {
            switch line.orientation {
            case .horizontal: line.row >= 0 && line.row <= rows && line.col >= 0 && line.col < cols
            case .vertical: line.row >= 0 && line.row < rows && line.col >= 0 && line.col <= cols
            }
        }

        public func index(of line: Line) -> Int {
            switch line.orientation {
            case .horizontal: line.row * cols + line.col
            case .vertical: horizontalCount + line.row * (cols + 1) + line.col
            }
        }

        public func line(at index: Int) -> Line {
            if index < horizontalCount { return .h(index / cols, index % cols) }
            let i = index - horizontalCount
            return .v(i / (cols + 1), i % (cols + 1))
        }

        public var allLines: [Line] { (0..<edgeCount).map(line(at:)) }

        /// The four sides of a box: top, bottom, left, right.
        public func lines(ofBox box: GridPoint) -> [Line] {
            [.h(box.row, box.col), .h(box.row + 1, box.col), .v(box.row, box.col), .v(box.row, box.col + 1)]
        }

        /// The one or two boxes a line borders.
        public func boxes(adjacentTo line: Line) -> [GridPoint] {
            var result: [GridPoint] = []
            switch line.orientation {
            case .horizontal:
                if line.row > 0 { result.append(GridPoint(row: line.row - 1, col: line.col)) }
                if line.row < rows { result.append(GridPoint(row: line.row, col: line.col)) }
            case .vertical:
                if line.col > 0 { result.append(GridPoint(row: line.row, col: line.col - 1)) }
                if line.col < cols { result.append(GridPoint(row: line.row, col: line.col)) }
            }
            return result
        }

        // MARK: State

        public func isDrawn(_ line: Line) -> Bool { drawn[index(of: line)] }
        public func owner(of line: Line) -> Player? { lineOwners[index(of: line)] }
        public func owner(ofBox box: GridPoint) -> Player? { boxOwners[box.row * cols + box.col] }

        /// Number of drawn sides of a box (0...4).
        public func sides(of box: GridPoint) -> Int {
            lines(ofBox: box).reduce(0) { $0 + (isDrawn($1) ? 1 : 0) }
        }

        private func sides(ofBox index: Int) -> Int {
            sides(of: GridPoint(row: index / cols, col: index % cols))
        }

        public var availableLines: [Line] {
            (0..<edgeCount).filter { !drawn[$0] }.map(line(at:))
        }

        public var linesRemaining: Int { drawn.lazy.filter { !$0 }.count }

        public func score(_ player: Player) -> Int {
            boxOwners.lazy.filter { $0 == player }.count
        }

        public var isOver: Bool { !drawn.contains(false) }

        /// The player with more boxes once the game is over (nil while playing or on a tie).
        public var winner: Player? {
            guard isOver else { return nil }
            let a = score(.one), b = score(.two)
            return a == b ? nil : (a > b ? .one : .two)
        }

        public var isTie: Bool { isOver && score(.one) == score(.two) }

        public var lastTurn: Turn? { history.last }

        /// Lines that complete a box right now.
        public var capturingLines: [Line] {
            availableLines.filter { line in boxes(adjacentTo: line).contains { sides(of: $0) == 3 } }
        }

        /// Lines that neither complete a box nor give the opponent one (no box reaches 3 sides).
        public var safeLines: [Line] {
            availableLines.filter { line in boxes(adjacentTo: line).allSatisfy { sides(of: $0) < 2 } }
        }

        // MARK: Moves

        /// Draws a line for the current player. Completing a box claims it and the same player
        /// moves again. Returns nil (and changes nothing) for an illegal move.
        @discardableResult
        public mutating func play(_ line: Line) -> Turn? {
            guard contains(line), !isDrawn(line) else { return nil }
            let i = index(of: line)
            drawn[i] = true
            lineOwners[i] = current
            var claimed: [GridPoint] = []
            for box in boxes(adjacentTo: line) where sides(of: box) == 4 {
                boxOwners[box.row * cols + box.col] = current
                claimed.append(box)
            }
            let turn = Turn(line: line, player: current, claimed: claimed)
            history.append(turn)
            if claimed.isEmpty { current = current.other }
            return turn
        }

        /// Takes back the last move. Returns it, or nil when there is nothing to undo.
        @discardableResult
        public mutating func undo() -> Turn? {
            guard let turn = history.popLast() else { return nil }
            let i = index(of: turn.line)
            drawn[i] = false
            lineOwners[i] = nil
            for box in turn.claimed { boxOwners[box.row * cols + box.col] = nil }
            current = turn.player
            return turn
        }
    }
}
