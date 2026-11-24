/// Water Sort: pour colored liquid between tubes until every tube holds a single color.
///
/// Tubes hold `capacity` layers. A pour moves the top run of same-colored layers onto an empty
/// tube or onto the same color, as much as fits. A full tube of one color is complete.
public enum WaterSort {
    /// Layers per tube.
    public static let capacity = 4
    /// Distinct liquid colors (`0..<paletteSize`).
    public static let paletteSize = 12
    /// Empty tubes every puzzle starts with.
    public static let emptyTubes = 2

    /// A liquid color index (`0..<paletteSize`).
    public typealias Liquid = Int

    /// One pour: `count` layers of `liquid` from tube `from` onto tube `to`.
    public struct Pour: Hashable, Codable, Sendable {
        public let from: Int
        public let to: Int
        public let count: Int
        public let liquid: Liquid

        public init(from: Int, to: Int, count: Int, liquid: Liquid) {
            self.from = from
            self.to = to
            self.count = count
            self.liquid = liquid
        }
    }

    /// The starting position of a puzzle: each tube's layers, bottom first.
    public struct Puzzle: Hashable, Codable, Sendable {
        public let tubes: [[Liquid]]

        public init(tubes: [[Liquid]]) {
            self.tubes = tubes
        }

        /// Distinct colors in the puzzle.
        public var colorCount: Int { Set(tubes.joined()).count }
    }

    public struct State: Codable, Equatable, Sendable {
        public let puzzle: Puzzle
        /// Each tube's layers, bottom first.
        public private(set) var tubes: [[Liquid]]
        /// Pours made, oldest first (undo pops them).
        public private(set) var history: [Pour] = []
        /// The one free extra tube has been added.
        public private(set) var extraTubeUsed = false

        public init(puzzle: Puzzle) {
            self.puzzle = puzzle
            self.tubes = puzzle.tubes
        }

        /// The puzzle with the given tubes as its start. Useful for tests.
        public init(tubes: [[Liquid]]) {
            self.init(puzzle: Puzzle(tubes: tubes))
        }

        // MARK: Queries

        public var moveCount: Int { history.count }
        public var canUndo: Bool { !history.isEmpty }
        public var isSolved: Bool { tubes.allSatisfy { $0.isEmpty || WaterSort.isComplete($0) } }

        public func isComplete(_ tube: Int) -> Bool { WaterSort.isComplete(tubes[tube]) }

        /// The pour from `from` onto `to`, or nil when it isn't allowed.
        public func pour(from: Int, to: Int) -> Pour? {
            WaterSort.pour(from: from, to: to, in: tubes)
        }

        public func canPour(from: Int, to: Int) -> Bool { pour(from: from, to: to) != nil }

        /// Tubes that `from` can pour into.
        public func targets(from: Int) -> [Int] {
            tubes.indices.filter { canPour(from: from, to: $0) }
        }

        /// Whether a tube is worth picking up: it has liquid and isn't already complete.
        public func canPick(_ tube: Int) -> Bool {
            tubes.indices.contains(tube) && !tubes[tube].isEmpty && !isComplete(tube)
        }

        /// Pours that change something: moving a single-colored tube into an empty one only shuffles it around.
        public var usefulPours: [Pour] { WaterSort.usefulPours(in: tubes) }
        /// No useful pour is left.
        public var isStuck: Bool { !isSolved && usefulPours.isEmpty }

        // MARK: Actions

        /// Pours `from` onto `to`. Returns the pour made, or nil when it isn't allowed.
        @discardableResult
        public mutating func apply(from: Int, to: Int) -> Pour? {
            guard let pour = pour(from: from, to: to) else { return nil }
            WaterSort.perform(pour, on: &tubes)
            history.append(pour)
            return pour
        }

        /// Takes back the last pour. Returns it, or nil when there is none.
        @discardableResult
        public mutating func undo() -> Pour? {
            guard let last = history.popLast() else { return nil }
            let moved = tubes[last.to].suffix(last.count)
            tubes[last.to].removeLast(last.count)
            tubes[last.from].append(contentsOf: moved)
            return last
        }

        /// Adds the one free empty tube. Returns false once it has been used.
        @discardableResult
        public mutating func addExtraTube() -> Bool {
            guard !extraTubeUsed else { return false }
            extraTubeUsed = true
            tubes.append([])
            return true
        }

        /// Back to the puzzle's start (the extra tube is available again).
        public mutating func restart() {
            tubes = puzzle.tubes
            history = []
            extraTubeUsed = false
        }
    }

    // MARK: Rules (shared with the solver)

    static func isComplete(_ tube: [Liquid]) -> Bool {
        tube.count == capacity && tube.allSatisfy { $0 == tube[0] }
    }

    /// Length of the run of the top color.
    static func topRun(_ tube: [Liquid]) -> Int {
        guard let top = tube.last else { return 0 }
        var n = 0
        for layer in tube.reversed() {
            guard layer == top else { break }
            n += 1
        }
        return n
    }

    static func pour(from: Int, to: Int, in tubes: [[Liquid]]) -> Pour? {
        guard from != to, tubes.indices.contains(from), tubes.indices.contains(to),
              let top = tubes[from].last else { return nil }
        let target = tubes[to]
        let room = capacity - target.count
        guard room > 0, target.last == nil || target.last == top else { return nil }
        return Pour(from: from, to: to, count: min(topRun(tubes[from]), room), liquid: top)
    }

    static func perform(_ pour: Pour, on tubes: inout [[Liquid]]) {
        tubes[pour.from].removeLast(pour.count)
        tubes[pour.to].append(contentsOf: repeatElement(pour.liquid, count: pour.count))
    }

    static func usefulPours(in tubes: [[Liquid]]) -> [Pour] {
        var result: [Pour] = []
        for from in tubes.indices where !tubes[from].isEmpty && !isComplete(tubes[from]) {
            let uniform = topRun(tubes[from]) == tubes[from].count
            for to in tubes.indices {
                guard let pour = pour(from: from, to: to, in: tubes) else { continue }
                if uniform && tubes[to].isEmpty { continue }
                result.append(pour)
            }
        }
        return result
    }
}
