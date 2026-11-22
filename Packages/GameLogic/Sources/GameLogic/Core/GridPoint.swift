/// A zero-based (row, column) coordinate on a rectangular grid.
public struct GridPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(row: lhs.row + rhs.row, col: lhs.col + rhs.col)
    }

    public var description: String { "(\(row),\(col))" }

    /// The 8 surrounding offsets (king moves).
    public static let neighborOffsets: [GridPoint] = [
        .init(row: -1, col: -1), .init(row: -1, col: 0), .init(row: -1, col: 1),
        .init(row: 0, col: -1), .init(row: 0, col: 1),
        .init(row: 1, col: -1), .init(row: 1, col: 0), .init(row: 1, col: 1),
    ]

    /// The 4 orthogonal offsets.
    public static let orthogonalOffsets: [GridPoint] = [
        .init(row: -1, col: 0), .init(row: 1, col: 0),
        .init(row: 0, col: -1), .init(row: 0, col: 1),
    ]

    public func isInside(rows: Int, cols: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < cols
    }
}

/// One of the four cardinal directions.
public enum Direction: String, CaseIterable, Codable, Sendable {
    case up, down, left, right

    public var offset: GridPoint {
        switch self {
        case .up: GridPoint(row: -1, col: 0)
        case .down: GridPoint(row: 1, col: 0)
        case .left: GridPoint(row: 0, col: -1)
        case .right: GridPoint(row: 0, col: 1)
        }
    }

    public var opposite: Direction {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}
