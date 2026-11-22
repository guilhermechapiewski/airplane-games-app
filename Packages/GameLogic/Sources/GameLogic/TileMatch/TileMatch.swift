/// Tile Match: a solitaire tile-matching game on 3D stacks.
///
/// Remove the board two tiles at a time by matching free tiles with matching faces. A tile is
/// free when nothing lies on top of it and its left or right side is open.
public enum TileMatch {
    public struct Tile: Identifiable, Hashable, Codable, Sendable {
        public let id: Int
        public let face: Face
        public var position: Position

        public init(id: Int, face: Face, position: Position) {
            self.id = id
            self.face = face
            self.position = position
        }
    }

    /// Two tile ids.
    public struct Pair: Hashable, Codable, Sendable {
        public let a: Int
        public let b: Int

        public init(_ a: Int, _ b: Int) {
            self.a = a
            self.b = b
        }

        public func contains(_ id: Int) -> Bool { a == id || b == id }
    }

    public enum Move: Codable, Equatable, Sendable {
        /// Two tiles were removed.
        case match(Tile, Tile)
        /// Tiles were rearranged; holds the arrangement (and solution) before the shuffle.
        case shuffle(tiles: [Tile], solution: [Pair])
    }

    public enum ShuffleResult: Equatable, Sendable {
        /// The new arrangement can definitely be cleared.
        case solvable
        /// The new arrangement has moves, but no full solution was found.
        case unsure
        /// No arrangement of the remaining tiles has a move (e.g. two tiles stacked on each other).
        case impossible
    }

    public struct State: Codable, Equatable, Sendable {
        public let layout: LayoutID
        /// Remaining tiles in painter's order.
        public private(set) var tiles: [Tile]
        /// A known way to clear the board from the dealt (or last shuffled) arrangement, in removal order.
        public private(set) var solution: [Pair]
        public private(set) var history: [Move]
        public private(set) var shuffleCount = 0
        private var rng: SeededRandom

        /// Deals a new game that is guaranteed to be solvable.
        public static func newGame(layout: LayoutID, seed: UInt64 = .random(in: .min ... .max)) -> State {
            var rng = SeededRandom(seed: seed)
            let positions = layout.layout.positions
            // The layouts are validated by tests; construction always succeeds within the attempt budget.
            guard let order = TileMatch.construct(positions: positions, using: &rng) else {
                preconditionFailure("layout \(layout) cannot be constructed")
            }
            let faces = TileMatch.facePairs(count: positions.count, using: &rng)
            var tiles: [Tile] = []
            var solution: [Pair] = []
            for (i, slots) in order.enumerated() {
                let a = Tile(id: 2 * i, face: faces[i].0, position: slots.0)
                let b = Tile(id: 2 * i + 1, face: faces[i].1, position: slots.1)
                tiles += [a, b]
                solution.append(Pair(a.id, b.id))
            }
            return State(layout: layout, tiles: tiles, solution: solution.reversed(), rng: rng)
        }

        /// Creates a state from explicit tiles. Useful for tests.
        public init(layout: LayoutID, tiles: [Tile], solution: [Pair] = [], seed: UInt64 = 1) {
            self.init(layout: layout, tiles: tiles, solution: solution, rng: SeededRandom(seed: seed))
        }

        private init(layout: LayoutID, tiles: [Tile], solution: [Pair], rng: SeededRandom) {
            self.layout = layout
            self.tiles = tiles.sorted { $0.position < $1.position }
            self.solution = solution
            self.history = []
            self.rng = rng
        }

        // MARK: Queries

        public var isCleared: Bool { tiles.isEmpty }
        public var occupied: Set<Position> { Set(tiles.map(\.position)) }
        public var matchesMade: Int {
            history.filter { if case .match = $0 { true } else { false } }.count
        }

        public func tile(_ id: Int) -> Tile? { tiles.first { $0.id == id } }

        public func isFree(_ id: Int) -> Bool {
            guard let t = tile(id) else { return false }
            return TileMatch.isFree(t.position, in: occupied)
        }

        public var freeTileIDs: Set<Int> {
            let occ = occupied
            return Set(tiles.filter { TileMatch.isFree($0.position, in: occ) }.map(\.id))
        }

        /// Ids of tiles with nothing lying on top of them (their whole face is visible).
        public var uncoveredTileIDs: Set<Int> {
            let occ = occupied
            return Set(tiles.filter { !$0.position.above.contains(where: occ.contains) }.map(\.id))
        }

        public func canMatch(_ a: Int, _ b: Int) -> Bool {
            guard a != b, let ta = tile(a), let tb = tile(b), ta.face.matches(tb.face) else { return false }
            let occ = occupied
            return TileMatch.isFree(ta.position, in: occ) && TileMatch.isFree(tb.position, in: occ)
        }

        /// Every pair of free tiles that match, in a stable order.
        public var availableMatches: [Pair] {
            let free = freeTileIDs
            let candidates = tiles.filter { free.contains($0.id) }
            var pairs: [Pair] = []
            for i in candidates.indices {
                for j in candidates.indices where j > i && candidates[i].face.matches(candidates[j].face) {
                    pairs.append(Pair(candidates[i].id, candidates[j].id))
                }
            }
            return pairs
        }

        public var hasMoves: Bool { !availableMatches.isEmpty }

        /// A free matching pair to suggest, preferring moves that keep the board solvable.
        public func hint() -> Pair? {
            let available = availableMatches
            guard !available.isEmpty else { return nil }
            let present = Set(tiles.map(\.id))
            // Follow the known solution while it still applies.
            if let next = solution.first(where: { present.contains($0.a) && present.contains($0.b) }),
               available.contains(next) || available.contains(Pair(next.b, next.a)) {
                return next
            }
            if let path = TileMatch.solve(tiles: tiles), let first = path.first { return first }
            return available.max { unblockScore($0) < unblockScore($1) }
        }

        /// How much removing a pair is likely to open up: higher tiles and tiles with neighbours first.
        private func unblockScore(_ pair: Pair) -> Int {
            let occ = occupied
            return [pair.a, pair.b].compactMap(tile).reduce(0) { total, t in
                let p = t.position
                let neighbours = (p.left + p.right + p.below).filter(occ.contains).count
                return total + p.z * 10 + neighbours
            }
        }

        // MARK: Moves

        /// Removes two free matching tiles. Returns `false` (and changes nothing) if the move is illegal.
        @discardableResult
        public mutating func match(_ a: Int, _ b: Int) -> Bool {
            guard canMatch(a, b), let ta = tile(a), let tb = tile(b) else { return false }
            tiles.removeAll { $0.id == a || $0.id == b }
            history.append(.match(ta, tb))
            return true
        }

        /// Reverts the latest match or shuffle.
        @discardableResult
        public mutating func undo() -> Move? {
            guard let last = history.popLast() else { return nil }
            switch last {
            case let .match(a, b):
                tiles.append(contentsOf: [a, b])
                tiles.sort { $0.position < $1.position }
            case let .shuffle(previous, previousSolution):
                tiles = previous
                solution = previousSolution
                shuffleCount = max(0, shuffleCount - 1)
            }
            return last
        }

        /// Rearranges the remaining tiles over the remaining slots, keeping the board solvable when possible.
        @discardableResult
        public mutating func shuffle() -> ShuffleResult {
            guard tiles.count >= 2 else { return .impossible }
            let before = tiles
            let previousSolution = solution
            let positions = tiles.map(\.position).sorted()

            // Group remaining tiles into matching pairs (always possible after whole-pair removals).
            var groups: [Face: [Tile]] = [:]
            for t in tiles.sorted(by: { $0.id < $1.id }) { groups[t.face.matchKey, default: []].append(t) }
            let keys = groups.keys.sorted { $0.description < $1.description }
            var tilePairs: [(Tile, Tile)] = []
            var paired = true
            for key in keys {
                let group = groups[key]!
                if !group.count.isMultiple(of: 2) { paired = false }
                for i in stride(from: 0, to: group.count - 1, by: 2) { tilePairs.append((group[i], group[i + 1])) }
            }

            var result: ShuffleResult = .impossible
            if paired, let order = TileMatch.construct(positions: positions, using: &rng, attempts: 20) {
                tilePairs.shuffle(using: &rng)
                var placed: [Tile] = []
                var newSolution: [Pair] = []
                for (i, slots) in order.enumerated() {
                    var a = tilePairs[i].0, b = tilePairs[i].1
                    a.position = slots.0
                    b.position = slots.1
                    placed += [a, b]
                    newSolution.append(Pair(a.id, b.id))
                }
                tiles = placed.sorted { $0.position < $1.position }
                solution = newSolution.reversed()
                result = .solvable
            } else {
                // Fall back to random arrangements that at least offer a move.
                for _ in 0..<60 {
                    let slots = positions.shuffled(using: &rng)
                    var candidate = before
                    for i in candidate.indices { candidate[i].position = slots[i] }
                    tiles = candidate.sorted { $0.position < $1.position }
                    if hasMoves {
                        solution = TileMatch.solve(tiles: tiles) ?? []
                        result = solution.isEmpty ? .unsure : .solvable
                        break
                    }
                }
                if result == .impossible {
                    tiles = before
                    return .impossible
                }
            }
            shuffleCount += 1
            history.append(.shuffle(tiles: before, solution: previousSolution))
            return result
        }
    }

    // MARK: - Construction

    /// Builds a removal-safe pairing of `positions` by placing pairs in reverse.
    ///
    /// Starting from an empty table, it repeatedly places two slots that rest on already placed
    /// tiles and would both be free right after placement, so removing the pairs in the opposite
    /// order is always legal. Placements that would leave some empty slot impossible to fill later
    /// are rejected, and dead ends are escaped by stepping back a few pairs.
    /// Returns pairs in placement order (the last pair is the first one to remove).
    static func construct<R: RandomNumberGenerator>(positions: [Position], using rng: inout R,
                                                    attempts: Int = 60) -> [(Position, Position)]? {
        let slots = positions.sorted()
        let n = slots.count
        guard n.isMultiple(of: 2) else { return nil }
        var index: [Position: Int] = [:]
        for (i, p) in slots.enumerated() { index[p] = i }
        func indices(_ ps: [Position]) -> [Int] { ps.compactMap { index[$0] } }

        let left = slots.map { indices($0.left) }
        let right = slots.map { indices($0.right) }
        let above = slots.map { indices($0.above) }
        let below = slots.map { indices($0.below) }
        // Everything reachable by repeatedly stepping left (or right) in the same layer.
        func closure(_ start: Int, _ step: [[Int]]) -> [Int] {
            var seen = Set<Int>(), stack = step[start], result: [Int] = []
            while let i = stack.popLast() {
                guard seen.insert(i).inserted else { continue }
                result.append(i)
                stack += step[i]
            }
            return result
        }
        let leftClosure = (0..<n).map { closure($0, left) }
        let rightClosure = (0..<n).map { closure($0, right) }
        // Slots whose viability depends on slot i being empty.
        var dependents = [[Int]](repeating: [], count: n)
        for q in 0..<n { for p in Set(leftClosure[q] + rightClosure[q]) { dependents[p].append(q) } }

        var placed = [Bool](repeating: false, count: n)
        func isFree(_ i: Int) -> Bool {
            !above[i].contains { placed[$0] } && (!left[i].contains { placed[$0] } || !right[i].contains { placed[$0] })
        }
        func canPlace(_ i: Int) -> Bool {
            !placed[i] && below[i].allSatisfy { placed[$0] } && isFree(i)
        }
        // An empty slot can only ever be filled (and be free at that moment) if everything on one
        // side of it is still empty: anything placed there first would block that side for good.
        func viable(_ i: Int) -> Bool {
            !leftClosure[i].contains { placed[$0] } || !rightClosure[i].contains { placed[$0] }
        }
        func keepsViable(_ p: Int) -> Bool { dependents[p].allSatisfy { placed[$0] || viable($0) } }

        // Random order with a preference for low layers, so stacks grow evenly.
        func candidates() -> [Int] {
            (0..<n).filter(canPlace)
                .map { ($0, Double.random(in: 0..<1, using: &rng) + Double(slots[$0].z)) }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }

        for _ in 0..<attempts {
            placed = [Bool](repeating: false, count: n)
            var order: [(Int, Int)] = []
            var backtracks = 0
            while order.count * 2 < n {
                var found: (Int, Int)?
                outer: for p1 in candidates() {
                    placed[p1] = true
                    for p2 in candidates() {
                        placed[p2] = true
                        if isFree(p1), isFree(p2), keepsViable(p1), keepsViable(p2) {
                            found = (p1, p2)
                            break outer
                        }
                        placed[p2] = false
                    }
                    placed[p1] = false
                }
                if let found {
                    order.append(found)
                    continue
                }
                // Dead end: undo a few random-length steps and try a different continuation.
                backtracks += 1
                guard backtracks <= 80, !order.isEmpty else { break }
                for _ in 0..<min(order.count, Int.random(in: 1...(2 + backtracks / 4), using: &rng)) {
                    let (a, b) = order.removeLast()
                    placed[a] = false
                    placed[b] = false
                }
            }
            if order.count * 2 == n { return order.map { (slots[$0.0], slots[$0.1]) } }
        }
        return nil
    }

    // MARK: - Solver

    /// Depth-first search for a full clearing sequence. Gives up after `budget` explored positions.
    public static func solve(tiles: [Tile], budget: Int = 4000) -> [Pair]? {
        let ids = tiles.map(\.id)
        guard let maxID = ids.max(), maxID < 256 else { return tiles.isEmpty ? [] : nil }
        var byID: [Int: Tile] = [:]
        for t in tiles { byID[t.id] = t }
        var occupied = Set(tiles.map(\.position))
        var remaining = Set(ids)
        var seen = Set<[UInt64]>()
        var nodes = 0
        var path: [Pair] = []

        func key() -> [UInt64] {
            var words = [UInt64](repeating: 0, count: 4)
            for id in remaining { words[id >> 6] |= 1 << UInt64(id & 63) }
            return words
        }

        func moves() -> [Pair] {
            let free = remaining.sorted().compactMap { byID[$0] }.filter { TileMatch.isFree($0.position, in: occupied) }
            var groups: [Face: [Tile]] = [:]
            for t in free { groups[t.face.matchKey, default: []].append(t) }
            var result: [Pair] = []
            for key in groups.keys.sorted(by: { $0.description < $1.description }) {
                let g = groups[key]!
                guard g.count >= 2 else { continue }
                // When every tile of a group is free, pairing them up is always safe: do just that.
                let total = remaining.reduce(0) { $0 + (byID[$1]!.face.matchKey == key ? 1 : 0) }
                if g.count == total { return [Pair(g[0].id, g[1].id)] }
                for i in g.indices { for j in g.indices where j > i { result.append(Pair(g[i].id, g[j].id)) } }
            }
            // Prefer removing high tiles that cover or flank many others.
            func score(_ p: Pair) -> Int {
                [p.a, p.b].reduce(0) { s, id in
                    let pos = byID[id]!.position
                    return s + pos.z * 8 + (pos.left + pos.right).filter(occupied.contains).count
                }
            }
            return result.sorted { score($0) > score($1) }
        }

        func search() -> Bool {
            if remaining.isEmpty { return true }
            nodes += 1
            if nodes > budget { return false }
            guard seen.insert(key()).inserted else { return false }
            for m in moves() {
                let a = byID[m.a]!, b = byID[m.b]!
                remaining.remove(m.a); remaining.remove(m.b)
                occupied.remove(a.position); occupied.remove(b.position)
                path.append(m)
                if search() { return true }
                path.removeLast()
                remaining.insert(m.a); remaining.insert(m.b)
                occupied.insert(a.position); occupied.insert(b.position)
                if nodes > budget { return false }
            }
            return false
        }

        return search() ? path : nil
    }
}
