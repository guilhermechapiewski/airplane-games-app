/// Snake: steer a growing snake around a grid, eat food, don't bite yourself (or the walls).
public enum Snake {
    public static let defaultSize = 15
    public static let startLength = 3
    /// Turns that can be buffered ahead of the next tick.
    public static let maxQueuedTurns = 2

    public enum Speed: String, CaseIterable, Codable, Sendable, Identifiable {
        case relaxed, normal, fast

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .relaxed: "Relaxed"
            case .normal: "Normal"
            case .fast: "Fast"
            }
        }

        /// Seconds between ticks.
        public var interval: Double {
            switch self {
            case .relaxed: 0.2
            case .normal: 0.135
            case .fast: 0.085
            }
        }
    }

    public enum WallMode: String, CaseIterable, Codable, Sendable {
        /// Leaving the board ends the game.
        case walls
        /// Leaving the board re-enters on the opposite side.
        case wrap
    }

    public enum Status: String, Codable, Sendable {
        case playing, won, lost
    }

    public enum DeathCause: String, Codable, Sendable {
        case wall, selfCollision
    }

    /// What happened during one tick.
    public struct TickResult: Equatable, Sendable {
        public var ate = false
        public var died: DeathCause?
        public var won = false
        /// The head crossed an edge in wrap mode.
        public var wrapped = false
    }

    public struct State: Codable, Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let wallMode: WallMode
        /// Head first.
        public private(set) var body: [GridPoint]
        /// The direction of the last move.
        public private(set) var direction: Direction
        /// Buffered turns, applied one per tick.
        public private(set) var queue: [Direction]
        public private(set) var food: GridPoint?
        public private(set) var score: Int
        public private(set) var status: Status
        public private(set) var deathCause: DeathCause?
        public private(set) var ticks: Int
        private var rng: SeededRandom

        public static func newGame(width: Int = defaultSize, height: Int = defaultSize,
                                   wallMode: WallMode = .walls,
                                   seed: UInt64 = .random(in: .min ... .max)) -> State {
            let row = height / 2
            let headCol = max(startLength - 1, width / 2 - 2)
            let body = (0..<startLength).map { GridPoint(row: row, col: headCol - $0) }
            var s = State(width: width, height: height, wallMode: wallMode, body: body,
                          direction: .right, food: nil, seed: seed)
            s.spawnFood()
            return s
        }

        /// Explicit state for tests.
        public init(width: Int, height: Int, wallMode: WallMode, body: [GridPoint], direction: Direction,
                    food: GridPoint?, seed: UInt64, score: Int = 0) {
            precondition(!body.isEmpty, "A snake needs a head")
            self.width = width
            self.height = height
            self.wallMode = wallMode
            self.body = body
            self.direction = direction
            self.queue = []
            self.food = food
            self.score = score
            self.status = .playing
            self.deathCause = nil
            self.ticks = 0
            self.rng = SeededRandom(seed: seed)
        }

        public var head: GridPoint { body[0] }
        public var length: Int { body.count }
        public var cellCount: Int { width * height }
        public var isOver: Bool { status != .playing }

        /// The direction the snake will move on the next tick.
        public var nextDirection: Direction { queue.first ?? direction }

        /// Buffers a turn. Ignored when it repeats or reverses the last buffered direction,
        /// or when the buffer is full. Returns whether the turn was accepted.
        @discardableResult
        public mutating func turn(_ newDirection: Direction) -> Bool {
            guard status == .playing, queue.count < maxQueuedTurns else { return false }
            let last = queue.last ?? direction
            guard newDirection != last, newDirection != last.opposite else { return false }
            queue.append(newDirection)
            return true
        }

        /// Advances the game by one step.
        @discardableResult
        public mutating func tick() -> TickResult {
            var result = TickResult()
            guard status == .playing else { return result }
            if !queue.isEmpty { direction = queue.removeFirst() }
            ticks += 1

            var next = head + direction.offset
            if !next.isInside(rows: height, cols: width) {
                if wallMode == .walls {
                    die(.wall)
                    result.died = .wall
                    return result
                }
                next = GridPoint(row: (next.row + height) % height, col: (next.col + width) % width)
                result.wrapped = true
            }

            let eating = next == food
            // The tail moves out of the way this tick unless we are growing.
            let obstacles = eating ? body[...] : body.dropLast()
            if obstacles.contains(next) {
                die(.selfCollision)
                result.died = .selfCollision
                return result
            }

            body.insert(next, at: 0)
            if eating {
                score += 1
                result.ate = true
                food = nil
                if body.count == cellCount {
                    status = .won
                    result.won = true
                } else {
                    spawnFood()
                }
            } else {
                body.removeLast()
            }
            return result
        }

        private mutating func die(_ cause: DeathCause) {
            status = .lost
            deathCause = cause
            queue = []
        }

        private mutating func spawnFood() {
            let occupied = Set(body)
            let free = cellCount - occupied.count
            guard free > 0 else {
                food = nil
                return
            }
            // Pick the n-th free cell so the draw is uniform without building a list.
            var n = Int.random(in: 0..<free, using: &rng)
            for r in 0..<height {
                for c in 0..<width {
                    let p = GridPoint(row: r, col: c)
                    guard !occupied.contains(p) else { continue }
                    if n == 0 {
                        food = p
                        return
                    }
                    n -= 1
                }
            }
        }
    }
}
