/// 2048: slide numbered tiles on a grid; equal tiles merge into their sum.
public enum TwentyFortyEight {
    public static let target = 2048

    public struct Tile: Identifiable, Hashable, Codable, Sendable {
        public let id: Int
        public var value: Int
        public var position: GridPoint
    }

    /// Everything the UI needs to animate a move.
    public struct Outcome: Equatable, Sendable {
        /// Tiles absorbed by a merge, with the position they slid into before disappearing.
        public var consumed: [Tile] = []
        /// Ids of surviving tiles whose value doubled this move.
        public var merged: Set<Int> = []
        public var scoreGained = 0
        /// The tile spawned after the move (set by `move`, not `slide`).
        public var spawned: Tile?
    }

    public struct State: Codable, Equatable, Sendable {
        public let size: Int
        public private(set) var tiles: [Tile]
        public private(set) var score: Int
        private var nextID: Int
        private var rng: SeededRandom

        public static func newGame(size: Int = 4, seed: UInt64 = .random(in: .min ... .max)) -> State {
            var s = State(size: size, tiles: [], score: 0, nextID: 0, rng: SeededRandom(seed: seed))
            s.spawnTile()
            s.spawnTile()
            return s
        }

        /// Creates a state from a row-major value grid (0 = empty). Useful for tests.
        public init(grid: [[Int]], seed: UInt64) {
            let size = grid.count
            var tiles: [Tile] = []
            var id = 0
            for r in 0..<size {
                for c in 0..<size where grid[r][c] != 0 {
                    tiles.append(Tile(id: id, value: grid[r][c], position: GridPoint(row: r, col: c)))
                    id += 1
                }
            }
            self.init(size: size, tiles: tiles, score: 0, nextID: id, rng: SeededRandom(seed: seed))
        }

        private init(size: Int, tiles: [Tile], score: Int, nextID: Int, rng: SeededRandom) {
            self.size = size
            self.tiles = tiles
            self.score = score
            self.nextID = nextID
            self.rng = rng
        }

        public var valueGrid: [[Int]] {
            var g = Array(repeating: Array(repeating: 0, count: size), count: size)
            for t in tiles { g[t.position.row][t.position.col] = t.value }
            return g
        }

        public var highestTile: Int { tiles.map(\.value).max() ?? 0 }
        public var hasWon: Bool { highestTile >= TwentyFortyEight.target }

        public var canMove: Bool {
            if tiles.count < size * size { return true }
            let g = valueGrid
            for r in 0..<size {
                for c in 0..<size {
                    if c + 1 < size, g[r][c] == g[r][c + 1] { return true }
                    if r + 1 < size, g[r][c] == g[r + 1][c] { return true }
                }
            }
            return false
        }

        /// Slides in `direction` and spawns a new tile. Returns `nil` if nothing moved.
        public mutating func move(_ direction: Direction) -> Outcome? {
            guard var outcome = slide(direction) else { return nil }
            outcome.spawned = spawnTile()
            return outcome
        }

        /// Slides and merges without spawning. Returns `nil` if nothing moved.
        mutating func slide(_ direction: Direction) -> Outcome? {
            var outcome = Outcome()
            var byPosition: [GridPoint: Tile] = [:]
            for t in tiles { byPosition[t.position] = t }

            var newTiles: [Tile] = []
            var moved = false

            for line in 0..<size {
                // Cells of this line ordered from the wall we slide toward.
                let cells = (0..<size).map { cell(line: line, index: $0, direction: direction) }
                let lineTiles = cells.compactMap { byPosition[$0] }
                var targetIndex = 0
                var i = 0
                while i < lineTiles.count {
                    var tile = lineTiles[i]
                    let destination = cells[targetIndex]
                    if i + 1 < lineTiles.count, lineTiles[i + 1].value == tile.value {
                        var absorbed = lineTiles[i + 1]
                        absorbed.position = destination
                        outcome.consumed.append(absorbed)
                        tile.value *= 2
                        outcome.merged.insert(tile.id)
                        outcome.scoreGained += tile.value
                        moved = true
                        i += 2
                    } else {
                        i += 1
                    }
                    if tile.position != destination { moved = true }
                    tile.position = destination
                    newTiles.append(tile)
                    targetIndex += 1
                }
            }

            guard moved else { return nil }
            tiles = newTiles
            score += outcome.scoreGained
            return outcome
        }

        private func cell(line: Int, index: Int, direction: Direction) -> GridPoint {
            switch direction {
            case .left: GridPoint(row: line, col: index)
            case .right: GridPoint(row: line, col: size - 1 - index)
            case .up: GridPoint(row: index, col: line)
            case .down: GridPoint(row: size - 1 - index, col: line)
            }
        }

        @discardableResult
        private mutating func spawnTile() -> Tile? {
            let occupied = Set(tiles.map(\.position))
            var empty: [GridPoint] = []
            for r in 0..<size {
                for c in 0..<size where !occupied.contains(GridPoint(row: r, col: c)) {
                    empty.append(GridPoint(row: r, col: c))
                }
            }
            guard let spot = empty.randomElement(using: &rng) else { return nil }
            let value = Int.random(in: 0..<10, using: &rng) == 0 ? 4 : 2
            let tile = Tile(id: nextID, value: value, position: spot)
            nextID += 1
            tiles.append(tile)
            return tile
        }
    }
}
