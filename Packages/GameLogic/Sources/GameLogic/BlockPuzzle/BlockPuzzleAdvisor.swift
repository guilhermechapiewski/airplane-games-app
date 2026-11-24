extension BlockPuzzle {
    /// Suggests where to put one of the tray's pieces.
    ///
    /// Every placement of every piece is tried, followed by the best ways to place the rest of
    /// the tray (in any order). A plan scores for: placing every piece (by far the most
    /// important), clearing lines (more at once is better), and leaving a tidy board: open space,
    /// no single-cell holes, few ragged edges, and room for the big pieces.
    public enum Advisor {
        public struct Suggestion: Equatable, Sendable {
            public let slot: Int
            public let origin: GridPoint
            /// Lines this placement clears right away.
            public let lines: Int
        }

        /// The suggested placement, or nil when no piece fits.
        public static func suggestion(for state: State) -> Suggestion? {
            let board = Bits(state.board)
            let pieces = state.tray.enumerated().compactMap { slot, piece in piece.map { (slot, Shape($0)) } }
            // Every first move, ranked by how it looks on its own; only the most promising are
            // planned through (which keeps a hint quick on an open board).
            var firsts: [(suggestion: Suggestion, board: Bits, rest: [Shape], quick: Double)] = []
            for (k, (slot, shape)) in pieces.enumerated() {
                var rest = pieces.map(\.1)
                rest.remove(at: k)
                for origin in shape.origins(on: board) {
                    let placed = board.placing(shape.mask(at: origin))
                    firsts.append((Suggestion(slot: slot, origin: origin, lines: placed.lines), placed.board, rest,
                                   gain(placed.lines) + placed.board.quality))
                }
            }
            firsts.sort { $0.quick > $1.quick }
            var best: (Suggestion, Double)?
            for first in firsts.prefix(rootBeam) {
                let value = gain(first.suggestion.lines) + plan(first.board, first.rest, beam: 10)
                if best == nil || value > best!.1 { best = (first.suggestion, value) }
            }
            return best?.0
        }

        /// How good a board is to keep playing on (higher is better). Exposed for tests.
        static func quality(_ board: Board) -> Double { Bits(board).quality }

        // MARK: Search

        private static let unplacedPenalty = 10_000.0
        /// First moves planned through in full.
        private static let rootBeam = 24

        private static func gain(_ lines: Int) -> Double {
            Double(30 * lines + 10 * lines * lines)
        }

        /// The best value reachable by placing all of `pieces` (any order), from `board`.
        /// Only the `beam` most promising placements of each piece are followed.
        private static func plan(_ board: Bits, _ pieces: [Shape], beam: Int) -> Double {
            guard !pieces.isEmpty else { return board.quality }
            var best: Double?
            for (k, shape) in pieces.enumerated() {
                var rest = pieces
                rest.remove(at: k)
                var options = shape.origins(on: board).map { origin -> (board: Bits, gain: Double, value: Double) in
                    let placed = board.placing(shape.mask(at: origin))
                    let g = gain(placed.lines)
                    return (placed.board, g, g + placed.board.quality)
                }
                guard !options.isEmpty else { continue }
                if options.count > beam {
                    options.sort { $0.value > $1.value }
                    options.removeLast(options.count - beam)
                }
                for option in options {
                    let v = option.gain + plan(option.board, rest, beam: max(4, beam / 2))
                    if best == nil || v > best! { best = v }
                }
            }
            // Some piece can't go anywhere: bad, but less bad the fewer pieces are stuck.
            return best ?? (board.quality - unplacedPenalty * Double(pieces.count))
        }

        // MARK: Bitboard

        /// A piece as a bit mask anchored at the board's top-left corner.
        struct Shape {
            let mask: UInt64
            let width: Int
            let height: Int

            init(_ piece: Piece) {
                var m: UInt64 = 0
                for c in piece.cells { m |= 1 << UInt64(c.row * size + c.col) }
                mask = m
                width = piece.width
                height = piece.height
            }

            func mask(at origin: GridPoint) -> UInt64 { mask << UInt64(origin.row * size + origin.col) }

            func fitsAnywhere(on board: Bits) -> Bool {
                guard width <= size, height <= size else { return false }
                for r in 0...(size - height) {
                    for c in 0...(size - width) where board.filled & (mask << UInt64(r * size + c)) == 0 {
                        return true
                    }
                }
                return false
            }

            func origins(on board: Bits) -> [GridPoint] {
                guard width <= size, height <= size else { return [] }
                var result: [GridPoint] = []
                for r in 0...(size - height) {
                    for c in 0...(size - width) where board.filled & mask(at: GridPoint(row: r, col: c)) == 0 {
                        result.append(GridPoint(row: r, col: c))
                    }
                }
                return result
            }
        }

        /// The board as 64 bits, row-major (bit `row * 8 + col` set = filled).
        struct Bits: Hashable {
            var filled: UInt64

            static let row0: UInt64 = 0xFF
            static let col0: UInt64 = 0x0101_0101_0101_0101
            static let col7: UInt64 = col0 << 7
            static let row7: UInt64 = row0 << 56

            init(_ board: Board) {
                var m: UInt64 = 0
                for (i, cell) in board.cells.enumerated() where cell != nil { m |= 1 << UInt64(i) }
                filled = m
            }

            init(filled: UInt64) { self.filled = filled }

            /// Drops a piece mask and clears full lines.
            func placing(_ piece: UInt64) -> (board: Bits, lines: Int) {
                let b = filled | piece
                var clear: UInt64 = 0
                var lines = 0
                for i in 0..<UInt64(size) {
                    let row = Self.row0 << (8 * i)
                    if b & row == row { clear |= row; lines += 1 }
                    let col = Self.col0 << i
                    if b & col == col { clear |= col; lines += 1 }
                }
                return (Bits(filled: b & ~clear), lines)
            }

            /// Open space, minus single-cell holes and ragged edges, plus room for big pieces.
            var quality: Double {
                let empty = ~filled
                // Neighbors filled (walls count as filled).
                let left = (filled << 1) | Self.col0
                let right = (filled >> 1) | Self.col7
                let up = (filled << 8) | Self.row0
                let down = (filled >> 8) | Self.row7
                let holes = empty & left & right & up & down
                let horizontal = (filled ^ (filled >> 1)) & ~Self.col7
                let vertical = (filled ^ (filled >> 8)) & ~Self.row7
                var score = Double(empty.nonzeroBitCount) * 2
                score -= Double(holes.nonzeroBitCount) * 25
                score -= Double(horizontal.nonzeroBitCount + vertical.nonzeroBitCount) * 3
                for shape in Self.roomShapes where shape.fitsAnywhere(on: self) { score += 18 }
                return score
            }

            /// Shapes worth keeping room for: the 3×3 square and the long bars.
            private static let roomShapes: [Shape] = [
                Shape(Piece(id: 0, rows: ["###", "###", "###"])),
                Shape(Piece(id: 0, rows: ["#####"])),
                Shape(Piece(id: 0, rows: ["#", "#", "#", "#", "#"])),
            ]
        }
    }
}
