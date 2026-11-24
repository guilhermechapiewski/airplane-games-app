extension DotsAndBoxes {
    /// A run of boxes that each have exactly two sides drawn, linked through their open sides.
    /// Once no safe lines remain, opening one gives its boxes away in a row.
    public struct Component: Equatable, Sendable {
        public enum Kind: String, Sendable { case chain, loop }
        public let kind: Kind
        public let boxes: [GridPoint]
        public var length: Int { boxes.count }
        /// Chains of 3+ and all loops: the ones worth keeping control for.
        public var isLong: Bool { kind == .loop || boxes.count >= 3 }
    }
}

extension DotsAndBoxes.Game {
    /// The chains and loops on the board (runs of two-sided boxes), longest first.
    public var components: [DotsAndBoxes.Component] {
        let g = DotsAndBoxes.Geometry(rows: rows, cols: cols)
        let p = DotsAndBoxes.Bits(self)
        return g.arms(p)
            .map { arm in
                DotsAndBoxes.Component(kind: arm.isLoop ? .loop : .chain,
                                       boxes: arm.boxes.map { GridPoint(row: $0 / cols, col: $0 % cols) })
            }
            .sorted { $0.length > $1.length }
    }
}

extension DotsAndBoxes {
    /// The drawn lines of a board as a 128-bit set (boards have at most 128 lines).
    struct Bits: Hashable, Sendable {
        var lo: UInt64 = 0
        var hi: UInt64 = 0

        init() {}

        init(_ game: Game) {
            for i in game.drawn.indices where game.drawn[i] { insert(i) }
        }

        @inline(__always) func contains(_ i: Int) -> Bool {
            i < 64 ? (lo >> UInt64(i)) & 1 == 1 : (hi >> UInt64(i - 64)) & 1 == 1
        }

        @inline(__always) mutating func insert(_ i: Int) {
            if i < 64 { lo |= 1 << UInt64(i) } else { hi |= 1 << UInt64(i - 64) }
        }

        var count: Int { lo.nonzeroBitCount + hi.nonzeroBitCount }
    }

    /// A maximal run of two-sided boxes ("coins with two strings").
    struct Arm {
        var boxes: [Int]
        /// The open lines at either end (equal for a single box whose sides both lead out).
        var ends: [Int]
        /// For a run of exactly two boxes, the line between them.
        var middle: Int?
        var isLoop: Bool
    }

    /// Precomputed adjacency for a board size.
    struct Geometry: Sendable {
        let rows: Int
        let cols: Int
        let edgeCount: Int
        let boxCount: Int
        /// Four line indices per box.
        let boxEdges: [Int]
        /// Two box indices per line (-1 = the board edge).
        let edgeBoxes: [Int]

        init(rows: Int, cols: Int) {
            self.rows = rows
            self.cols = cols
            let h = (rows + 1) * cols
            edgeCount = h + rows * (cols + 1)
            boxCount = rows * cols
            var be: [Int] = []
            be.reserveCapacity(boxCount * 4)
            for r in 0..<rows {
                for c in 0..<cols {
                    be += [r * cols + c, (r + 1) * cols + c, h + r * (cols + 1) + c, h + r * (cols + 1) + c + 1]
                }
            }
            boxEdges = be
            var eb = Array(repeating: -1, count: edgeCount * 2)
            for box in 0..<boxCount {
                for k in 0..<4 {
                    let e = be[box * 4 + k]
                    if eb[e * 2] == -1 { eb[e * 2] = box } else { eb[e * 2 + 1] = box }
                }
            }
            edgeBoxes = eb
        }

        var full: Bits {
            var b = Bits()
            for i in 0..<edgeCount { b.insert(i) }
            return b
        }

        /// Undrawn sides of a box.
        @inline(__always) func degree(_ box: Int, _ p: Bits) -> Int {
            var d = 0
            for k in 0..<4 where !p.contains(boxEdges[box * 4 + k]) { d += 1 }
            return d
        }

        /// The box across `edge` from `box` (-1 = outside the board).
        @inline(__always) func across(_ edge: Int, from box: Int) -> Int {
            edgeBoxes[edge * 2] == box ? edgeBoxes[edge * 2 + 1] : edgeBoxes[edge * 2]
        }

        /// The undrawn sides of a box.
        func openEdges(_ box: Int, _ p: Bits) -> [Int] {
            (0..<4).map { boxEdges[box * 4 + $0] }.filter { !p.contains($0) }
        }

        /// Draws a line; returns the new position and how many boxes it completed.
        @inline(__always) func apply(_ edge: Int, _ p: Bits) -> (Bits, Int) {
            var q = p
            q.insert(edge)
            var completed = 0
            for k in 0..<2 {
                let b = edgeBoxes[edge * 2 + k]
                if b >= 0 && degree(b, q) == 0 { completed += 1 }
            }
            return (q, completed)
        }

        func isSafe(_ edge: Int, _ p: Bits) -> Bool {
            for k in 0..<2 {
                let b = edgeBoxes[edge * 2 + k]
                if b >= 0 && degree(b, p) <= 2 { return false }
            }
            return true
        }

        func safeEdges(_ p: Bits) -> [Int] {
            (0..<edgeCount).filter { !p.contains($0) && isSafe($0, p) }
        }

        func undrawn(_ p: Bits) -> [Int] {
            (0..<edgeCount).filter { !p.contains($0) }
        }

        /// Boxes with three sides drawn.
        func capturable(_ p: Bits) -> [Int] {
            (0..<boxCount).filter { degree($0, p) == 1 }
        }

        /// The edge that completes a three-sided box.
        func lastEdge(_ box: Int, _ p: Bits) -> Int {
            for k in 0..<4 where !p.contains(boxEdges[box * 4 + k]) { return boxEdges[box * 4 + k] }
            preconditionFailure("box is complete")
        }

        /// All maximal runs of two-sided boxes.
        func arms(_ p: Bits) -> [Arm] {
            var visited = Array(repeating: false, count: boxCount)
            var result: [Arm] = []
            for start in 0..<boxCount where !visited[start] && degree(start, p) == 2 {
                visited[start] = true
                let open = openEdges(start, p)
                // Walk one way, then the other.
                var sides: [[Int]] = [[], []]
                var endEdges: [Int] = [open[0], open[1]]
                var isLoop = false
                for dir in 0..<2 {
                    var cur = start
                    var via = open[dir]
                    while true {
                        let next = across(via, from: cur)
                        if next == start { isLoop = true; break }
                        if next < 0 || degree(next, p) != 2 || visited[next] {
                            endEdges[dir] = via
                            break
                        }
                        visited[next] = true
                        sides[dir].append(next)
                        let nextOpen = openEdges(next, p)
                        via = nextOpen[0] == via ? nextOpen[1] : nextOpen[0]
                        cur = next
                    }
                    if isLoop { break }
                }
                let boxes = sides[1].reversed() + [start] + sides[0]
                if isLoop {
                    result.append(Arm(boxes: boxes, ends: [open[0]], middle: nil, isLoop: true))
                } else {
                    var middle: Int?
                    if boxes.count == 2 {
                        middle = openEdges(boxes[0], p).first { across($0, from: boxes[0]) == boxes[1] }
                    }
                    let ends = endEdges[0] == endEdges[1] ? [endEdges[0]] : endEdges
                    result.append(Arm(boxes: boxes, ends: ends, middle: middle, isLoop: false))
                }
            }
            return result
        }
    }
}
