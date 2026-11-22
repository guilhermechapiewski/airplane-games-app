import Foundation

/// Word Search: find themed words hidden in a grid of letters.
public enum WordSearch {
    /// Every straight-line step (8 directions).
    public static let allDirections: [GridPoint] = GridPoint.neighborOffsets

    public struct Settings: Equatable, Sendable {
        public let size: Int
        public let wordCount: Int
        public let directions: [GridPoint]
    }

    public static func settings(for difficulty: Difficulty) -> Settings {
        let right = GridPoint(row: 0, col: 1), down = GridPoint(row: 1, col: 0)
        switch difficulty {
        case .easy:
            return Settings(size: 8, wordCount: 6, directions: [right, down])
        case .medium:
            return Settings(size: 10, wordCount: 8,
                            directions: [right, down, GridPoint(row: 1, col: 1), GridPoint(row: -1, col: 1)])
        case .hard, .expert:
            return Settings(size: 12, wordCount: 10, directions: allDirections)
        }
    }

    public struct Placement: Codable, Hashable, Sendable {
        public let word: String
        public let start: GridPoint
        public let step: GridPoint

        public var end: GridPoint { cell(word.count - 1) }
        public var cells: [GridPoint] { (0..<word.count).map(cell) }

        private func cell(_ i: Int) -> GridPoint {
            GridPoint(row: start.row + step.row * i, col: start.col + step.col * i)
        }
    }

    /// The straight line of cells from `a` to `b` (inclusive), or `nil` if they are not aligned
    /// horizontally, vertically or diagonally.
    public static func line(from a: GridPoint, to b: GridPoint) -> [GridPoint]? {
        let dr = b.row - a.row, dc = b.col - a.col
        guard dr == 0 || dc == 0 || abs(dr) == abs(dc) else { return nil }
        let n = max(abs(dr), abs(dc))
        let step = GridPoint(row: dr.signum(), col: dc.signum())
        return (0...n).map { GridPoint(row: a.row + step.row * $0, col: a.col + step.col * $0) }
    }

    /// Snaps a free drag from `start` toward `point` (fractional grid coordinates) to the nearest of
    /// the 8 directions, clamped inside the grid. Returns the end cell.
    public static func snappedEnd(from start: GridPoint, toward point: (row: Double, col: Double), size: Int) -> GridPoint {
        let dy = point.row - Double(start.row), dx = point.col - Double(start.col)
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= 0.5 else { return start }
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let octant = Int((angle / (Double.pi / 4)).rounded()) & 7
        let steps: [GridPoint] = [
            .init(row: 0, col: 1), .init(row: 1, col: 1), .init(row: 1, col: 0), .init(row: 1, col: -1),
            .init(row: 0, col: -1), .init(row: -1, col: -1), .init(row: -1, col: 0), .init(row: -1, col: 1),
        ]
        let step = steps[octant]
        let diagonal = step.row != 0 && step.col != 0
        // Project the drag onto the chosen direction.
        var length = Int(((dx * Double(step.col) + dy * Double(step.row)) / (diagonal ? 2 : 1)).rounded())
        length = max(0, length)
        while length > 0 {
            let end = GridPoint(row: start.row + step.row * length, col: start.col + step.col * length)
            if end.isInside(rows: size, cols: size) { return end }
            length -= 1
        }
        return start
    }

    public struct Puzzle: Codable, Equatable, Sendable {
        public let size: Int
        /// Row-major single-letter strings (lowercase).
        public let cells: [String]
        public let placements: [Placement]
        public let title: String

        public func letter(at p: GridPoint) -> String { cells[p.row * size + p.col] }

        public var words: [String] { placements.map(\.word) }

        func text(along cells: [GridPoint]) -> String { cells.map { letter(at: $0) }.joined() }

        /// The index of the placement exactly covered by the selection (either direction).
        public func placementIndex(from a: GridPoint, to b: GridPoint) -> Int? {
            guard a.isInside(rows: size, cols: size), b.isInside(rows: size, cols: size),
                  let line = WordSearch.line(from: a, to: b), line.count >= 2 else { return nil }
            return placements.firstIndex { p in
                let cells = p.cells
                return cells == line || cells == line.reversed()
            }
        }

        /// Number of distinct cell paths spelling `word` in any of the 8 directions.
        public func occurrences(of word: String) -> Int {
            var paths = Set<[GridPoint]>()
            let letters = word.map(String.init)
            for r in 0..<size {
                for c in 0..<size where cells[r * size + c] == letters[0] {
                    for step in WordSearch.allDirections {
                        var path: [GridPoint] = []
                        var ok = true
                        for i in 0..<letters.count {
                            let p = GridPoint(row: r + step.row * i, col: c + step.col * i)
                            guard p.isInside(rows: size, cols: size), letter(at: p) == letters[i] else { ok = false; break }
                            path.append(p)
                        }
                        if ok { paths.insert(path.sorted { ($0.row, $0.col) < ($1.row, $1.col) }) }
                    }
                }
            }
            return paths.count
        }

        /// Every string of length 3...`maxLength` readable in a straight line (used for safety checks).
        func lines(maxLength: Int) -> Set<String> {
            var result = Set<String>()
            for r in 0..<size {
                for c in 0..<size {
                    for step in WordSearch.allDirections {
                        var s = ""
                        for i in 0..<maxLength {
                            let p = GridPoint(row: r + step.row * i, col: c + step.col * i)
                            guard p.isInside(rows: size, cols: size) else { break }
                            s += letter(at: p)
                            if s.count >= 3 { result.insert(s) }
                        }
                    }
                }
            }
            return result
        }
    }

    // MARK: Generation

    /// Picks `count` words that fit a `size` grid, none containing another (or its reverse).
    static func chooseWords<R: RandomNumberGenerator>(from pool: [String], count: Int, size: Int, using rng: inout R) -> [String] {
        var chosen: [String] = []
        for word in pool.shuffled(using: &rng) where word.count <= size && word.count >= 3 {
            let reversed = String(word.reversed())
            let conflicts = chosen.contains { other in
                other.contains(word) || other.contains(reversed) || word.contains(other) || reversed.contains(other)
            }
            if !conflicts { chosen.append(word) }
            if chosen.count == count { break }
        }
        return chosen
    }

    /// Places all `words` (lowercase a–z) in a grid, or returns `nil` if it could not.
    /// Guarantees every word appears exactly once and no blocklisted word appears by accident.
    public static func generate<R: RandomNumberGenerator>(
        words: [String], size: Int, directions: [GridPoint], title: String, using rng: inout R, attempts: Int = 200
    ) -> Puzzle? {
        let sorted = words.sorted { $0.count > $1.count }
        guard let longest = sorted.first, longest.count <= size else { return nil }
        for _ in 0..<attempts {
            guard let (grid, placements) = place(sorted, size: size, directions: directions, using: &rng) else { continue }
            for _ in 0..<12 {
                var filled = grid
                for i in filled.indices where filled[i] == nil {
                    filled[i] = String(fillerAlphabet.randomElement(using: &rng)!)
                }
                let puzzle = Puzzle(size: size, cells: filled.map { $0! },
                                    placements: words.map { w in placements.first { $0.word == w }! }, title: title)
                if isAcceptable(puzzle) { return puzzle }
            }
        }
        return nil
    }

    /// Weighted toward common letters so the grid looks like English without giving words away.
    static let fillerAlphabet: [Character] = Array("aaabbccdddeeeeffgghhhiiijkllmmnnnooopprrrsssstttuuvwwxyyz")

    static func isAcceptable(_ puzzle: Puzzle) -> Bool {
        for w in puzzle.words where puzzle.occurrences(of: w) != 1 { return false }
        let maxBlocked = WordLists.blocklist.map(\.count).max() ?? 0
        let readable = puzzle.lines(maxLength: min(maxBlocked, puzzle.size))
        return readable.isDisjoint(with: WordLists.blocklist)
    }

    private static func place<R: RandomNumberGenerator>(
        _ words: [String], size: Int, directions: [GridPoint], using rng: inout R
    ) -> ([String?], [Placement])? {
        var grid = [String?](repeating: nil, count: size * size)
        var placements: [Placement] = []
        for word in words {
            let letters = word.map(String.init)
            var fits: [(Placement, Int)] = []
            for r in 0..<size {
                for c in 0..<size {
                    for step in directions {
                        let end = GridPoint(row: r + step.row * (letters.count - 1), col: c + step.col * (letters.count - 1))
                        guard end.isInside(rows: size, cols: size) else { continue }
                        var overlap = 0
                        var ok = true
                        for i in 0..<letters.count {
                            let existing = grid[(r + step.row * i) * size + c + step.col * i]
                            if let existing {
                                if existing == letters[i] { overlap += 1 } else { ok = false; break }
                            }
                        }
                        // A word must never sit entirely on top of letters already placed.
                        if ok && overlap < letters.count {
                            fits.append((Placement(word: word, start: GridPoint(row: r, col: c), step: step), overlap))
                        }
                    }
                }
            }
            guard !fits.isEmpty else { return nil }
            // Lean toward crossings for a denser, more interesting grid.
            let crossing = fits.filter { $0.1 > 0 }
            let pool = !crossing.isEmpty && Bool.random(using: &rng) ? crossing : fits
            let chosen = pool.randomElement(using: &rng)!.0
            for (i, p) in chosen.cells.enumerated() { grid[p.row * size + p.col] = letters[i] }
            placements.append(chosen)
        }
        return (grid, placements)
    }

    /// Generates a puzzle for a category and difficulty. Always succeeds for the built-in categories.
    public static func generate<R: RandomNumberGenerator>(
        category: WordCategory, difficulty: Difficulty, using rng: inout R
    ) -> Puzzle {
        let s = settings(for: difficulty)
        let pool = category.singleWords(minLength: 3, maxLength: s.size).filter { WordLists.isClean($0) }
        for _ in 0..<50 {
            let words = chooseWords(from: pool, count: s.wordCount, size: s.size, using: &rng)
            if let puzzle = generate(words: words, size: s.size, directions: s.directions, title: category.title, using: &rng, attempts: 40) {
                return puzzle
            }
        }
        // Extremely unlikely: fall back to fewer words.
        let words = chooseWords(from: pool, count: max(3, s.wordCount / 2), size: s.size, using: &rng)
        return generate(words: words, size: s.size, directions: s.directions, title: category.title, using: &rng)!
    }

    // MARK: Play state

    public enum SelectionResult: Equatable, Sendable {
        case found(Int)
        case alreadyFound(Int)
        case miss
    }

    public struct State: Codable, Equatable, Sendable {
        public let puzzle: Puzzle
        public let difficulty: Difficulty
        /// Placement indices in the order they were found.
        public private(set) var found: [Int] = []
        public private(set) var hintsUsed = 0

        public init(puzzle: Puzzle, difficulty: Difficulty) {
            self.puzzle = puzzle
            self.difficulty = difficulty
        }

        public var isComplete: Bool { found.count == puzzle.placements.count }
        public var remaining: [Int] { puzzle.placements.indices.filter { !found.contains($0) } }

        public func isFound(_ index: Int) -> Bool { found.contains(index) }

        @discardableResult
        public mutating func select(from a: GridPoint, to b: GridPoint) -> SelectionResult {
            guard let index = puzzle.placementIndex(from: a, to: b) else { return .miss }
            if found.contains(index) { return .alreadyFound(index) }
            found.append(index)
            return .found(index)
        }

        /// A remaining word to hint at (the first in list order), counting the hint.
        public mutating func useHint() -> Int? {
            guard let index = remaining.first else { return nil }
            hintsUsed += 1
            return index
        }
    }
}
