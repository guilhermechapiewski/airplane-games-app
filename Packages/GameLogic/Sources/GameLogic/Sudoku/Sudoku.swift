/// Sudoku: fill a 9×9 grid so every row, column and 3×3 box contains 1–9 once.
///
/// Grids are stored row-major as 81 `Int`s where `0` means empty. Candidate and
/// note sets are 16-bit masks using bits 1…9 (bit `d` set ⇔ digit `d` present).
public enum Sudoku {
    public static let side = 9
    public static let cellCount = 81
    /// Mask with bits 1…9 set.
    public static let allDigits: UInt16 = 0b11_1111_1110

    /// A row, column or 3×3 box.
    public enum Unit: Hashable, Codable, Sendable {
        case row(Int)
        case column(Int)
        case box(Int)

        /// Cell indices of the unit in reading order.
        public var cells: [Int] {
            switch self {
            case .row(let r): Sudoku.rows[r]
            case .column(let c): Sudoku.columns[c]
            case .box(let b): Sudoku.boxes[b]
            }
        }
    }

    // MARK: - Geometry

    @inline(__always) public static func row(of i: Int) -> Int { i / 9 }
    @inline(__always) public static func column(of i: Int) -> Int { i % 9 }
    @inline(__always) public static func box(of i: Int) -> Int { (i / 27) * 3 + (i % 9) / 3 }
    @inline(__always) public static func index(row: Int, column: Int) -> Int { row * 9 + column }

    public static let rows: [[Int]] = (0..<9).map { r in (0..<9).map { r * 9 + $0 } }
    public static let columns: [[Int]] = (0..<9).map { c in (0..<9).map { $0 * 9 + c } }
    public static let boxes: [[Int]] = (0..<9).map { b in
        let r0 = (b / 3) * 3, c0 = (b % 3) * 3
        return (0..<9).map { (r0 + $0 / 3) * 9 + c0 + $0 % 3 }
    }
    /// All 27 units: rows 0–8, columns 9–17, boxes 18–26.
    static let allUnits: [[Int]] = rows + columns + boxes

    /// The 20 cells sharing a row, column or box with each cell.
    public static let peers: [[Int]] = (0..<81).map { i in
        (0..<81).filter { $0 != i && areSeen($0, i) }
    }

    /// The three units containing a cell.
    public static func units(of i: Int) -> [Unit] {
        [.row(row(of: i)), .column(column(of: i)), .box(box(of: i))]
    }

    /// Whether two distinct cells share a row, column or box.
    @inline(__always) public static func areSeen(_ a: Int, _ b: Int) -> Bool {
        a != b && (row(of: a) == row(of: b) || column(of: a) == column(of: b) || box(of: a) == box(of: b))
    }

    // MARK: - Masks

    /// Digits (ascending) contained in a mask.
    public static func digits(in mask: UInt16) -> [Int] {
        (1...9).filter { mask & (1 << $0) != 0 }
    }

    @inline(__always) static func bit(_ digit: Int) -> UInt16 { 1 << UInt16(digit) }

    // MARK: - Validation

    /// Indices of filled cells whose digit repeats in one of their units.
    public static func conflicts(in grid: [Int]) -> Set<Int> {
        var result = Set<Int>()
        for unit in allUnits {
            var seen = [Int](repeating: -1, count: 10)
            for i in unit {
                let d = grid[i]
                guard d != 0 else { continue }
                if seen[d] >= 0 {
                    result.insert(i)
                    result.insert(seen[d])
                } else {
                    seen[d] = i
                }
            }
        }
        return result
    }

    /// `true` when every cell is filled and no unit repeats a digit.
    public static func isSolved(_ grid: [Int]) -> Bool {
        grid.count == cellCount && !grid.contains(0) && conflicts(in: grid).isEmpty
    }

    /// Digits that may legally go in an empty cell given the filled cells around it.
    public static func candidates(in grid: [Int], at i: Int) -> UInt16 {
        guard grid[i] == 0 else { return 0 }
        var used: UInt16 = 0
        for p in peers[i] where grid[p] != 0 { used |= bit(grid[p]) }
        return allDigits & ~used
    }
}
