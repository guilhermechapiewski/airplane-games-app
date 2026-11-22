extension TileMatch {
    /// A tile slot in a 3D stack.
    ///
    /// `x` and `y` are measured in **half tiles**, so a tile covers `[x, x+2) × [y, y+2)` and
    /// neighbours can be offset by half a tile. `z` is the layer (0 = table).
    public struct Position: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
        public let x: Int
        public let y: Int
        public let z: Int

        public init(x: Int, y: Int, z: Int) {
            self.x = x
            self.y = y
            self.z = z
        }

        /// Whether the two footprints overlap when seen from above (ignoring layers).
        public func overlapsFootprint(of other: Position) -> Bool {
            abs(x - other.x) < 2 && abs(y - other.y) < 2
        }

        /// Painter's order: lower layers first, then top-left to bottom-right so each tile's
        /// raised edge (drawn on its bottom-right) is covered by the neighbour that touches it.
        public static func < (a: Position, b: Position) -> Bool {
            if a.z != b.z { return a.z < b.z }
            if a.x + a.y != b.x + b.y { return a.x + a.y < b.x + b.y }
            return a.x < b.x
        }

        public var description: String { "(\(x),\(y),\(z))" }

        /// Slots on the layer above whose footprint overlaps this one.
        var above: [Position] { footprintNeighbors(z: z + 1) }
        /// Slots on the layer below whose footprint overlaps this one.
        var below: [Position] { footprintNeighbors(z: z - 1) }
        /// Slots that touch this one on its left side in the same layer.
        var left: [Position] { (-1...1).map { Position(x: x - 2, y: y + $0, z: z) } }
        /// Slots that touch this one on its right side in the same layer.
        var right: [Position] { (-1...1).map { Position(x: x + 2, y: y + $0, z: z) } }

        private func footprintNeighbors(z: Int) -> [Position] {
            var result: [Position] = []
            result.reserveCapacity(9)
            for dy in -1...1 {
                for dx in -1...1 { result.append(Position(x: x + dx, y: y + dy, z: z)) }
            }
            return result
        }
    }

    /// `true` if nothing in `occupied` lies on top of `p` and at least one side (left or right) is open.
    public static func isFree(_ p: Position, in occupied: Set<Position>) -> Bool {
        if p.above.contains(where: occupied.contains) { return false }
        let leftOpen = !p.left.contains(where: occupied.contains)
        let rightOpen = !p.right.contains(where: occupied.contains)
        return leftOpen || rightOpen
    }

    public enum LayoutID: String, CaseIterable, Codable, Sendable, Identifiable {
        case pebble, lantern, pyramid, bridge, butterfly, fortress

        public var id: String { rawValue }
        public var layout: Layout { Layout.all[self]! }
        public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// An original arrangement of tile slots.
    public struct Layout: Sendable {
        public let id: LayoutID
        /// Slots sorted in painter's order.
        public let positions: [Position]

        public var tileCount: Int { positions.count }
        public var maxZ: Int { positions.map(\.z).max() ?? 0 }
        /// Bounds in half-tile units: minimum corner and full extent (including the 2-unit tile size).
        public var bounds: (minX: Int, minY: Int, width: Int, height: Int) {
            let xs = positions.map(\.x), ys = positions.map(\.y)
            let minX = xs.min() ?? 0, minY = ys.min() ?? 0
            return (minX, minY, (xs.max() ?? 0) - minX + 2, (ys.max() ?? 0) - minY + 2)
        }

        /// One piece of a layer: `#` marks a tile at (column, row) in whole tiles, shifted by
        /// `dx`/`dy` half tiles.
        struct Piece {
            var z: Int
            var dx = 0
            var dy = 0
            var rows: [String]
        }

        init(id: LayoutID, pieces: [Piece]) {
            var result: [Position] = []
            for piece in pieces {
                for (r, row) in piece.rows.enumerated() {
                    for (c, ch) in row.enumerated() where ch == "#" {
                        result.append(Position(x: 2 * c + piece.dx, y: 2 * r + piece.dy, z: piece.z))
                    }
                }
            }
            self.id = id
            self.positions = result.sorted()
        }

        static let all: [LayoutID: Layout] = Dictionary(uniqueKeysWithValues: [
            pebble, lantern, pyramid, bridge, butterfly, fortress,
        ].map { ($0.id, $0) })

        /// 36 tiles — a quick game for phones.
        static let pebble = Layout(id: .pebble, pieces: [
            Piece(z: 0, rows: ["######", "######", "######", "######"]),
            Piece(z: 0, dx: -2, dy: 3, rows: ["#"]),
            Piece(z: 0, dx: 12, dy: 3, rows: ["#"]),
            Piece(z: 1, dx: 2, dy: 2, rows: ["####", "####"]),
            Piece(z: 2, dx: 4, dy: 3, rows: ["##"]),
        ])

        /// 66 tiles — a rounded lantern.
        static let lantern = Layout(id: .lantern, pieces: [
            Piece(z: 0, rows: [
                "..####..",
                ".######.",
                "########",
                "########",
                "########",
                "########",
                ".######.",
                "..####..",
            ]),
            Piece(z: 1, dx: 4, dy: 3, rows: ["####", "####", "####"]),
            Piece(z: 2, dx: 6, dy: 5, rows: ["##"]),
        ])

        /// 82 tiles — four stepped layers.
        static let pyramid = Layout(id: .pyramid, pieces: [
            Piece(z: 0, rows: Array(repeating: "########", count: 6)),
            Piece(z: 1, dx: 2, dy: 2, rows: Array(repeating: "######", count: 4)),
            Piece(z: 2, dx: 4, dy: 4, rows: Array(repeating: "####", count: 2)),
            Piece(z: 3, dx: 6, dy: 5, rows: ["##"]),
        ])

        /// 104 tiles — two towers joined by a span.
        static let bridge = Layout(id: .bridge, pieces: [
            Piece(z: 0, rows: [
                "###......###",
                "############",
                "############",
                "############",
                "###......###",
            ]),
            Piece(z: 1, rows: [
                "###......###",
                "###......###",
                "############",
                "###......###",
                "###......###",
            ]),
            Piece(z: 2, dx: 1, dy: 1, rows: Array(repeating: "##.......##", count: 4)),
            Piece(z: 3, dx: 2, dy: 3, rows: ["#........#", "#........#"]),
        ])

        /// 134 tiles — two layered wings around a raised body.
        static let butterfly = Layout(id: .butterfly, pieces: [
            Piece(z: 0, rows: [
                "##.........##",
                "####..#..####",
                "#####.#.#####",
                "#############",
                "#############",
                "#####.#.#####",
                "####..#..####",
                "##.........##",
            ]),
            Piece(z: 1, rows: [
                ".............",
                ".##.......##.",
                ".###.....###.",
                ".####.#.####.",
                ".####.#.####.",
                ".###.....###.",
                ".##.......##.",
            ]),
            Piece(z: 2, rows: [
                ".............",
                ".............",
                "..##.....##..",
                "..###.#.###..",
                "..###.#.###..",
                "..##.....##..",
            ]),
        ])

        /// 144 tiles — walls with corner towers around a central keep.
        static let fortress = Layout(id: .fortress, pieces: [
            Piece(z: 0, rows: Array(repeating: "############", count: 8)),
            Piece(z: 1, rows: [
                "############",
                "#..........#",
                "#..........#",
                "#...####...#",
                "#...####...#",
                "#..........#",
                "#..........#",
                "#####..#####",
            ]),
            Piece(z: 2, rows: [
                "#..........#",
                "............",
                "............",
                "............",
                "............",
                "............",
                "............",
                "#..........#",
            ]),
            Piece(z: 2, dx: 10, dy: 7, rows: ["##"]),
        ])
    }
}
