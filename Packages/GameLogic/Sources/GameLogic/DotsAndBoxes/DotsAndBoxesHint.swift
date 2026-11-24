extension DotsAndBoxes {
    /// A suggested line for the player to move, with the idea behind it.
    public struct Hint: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Completes one or two boxes.
            case take(boxes: Int)
            /// Neither completes a box nor gives one away.
            case safe
            /// Declines the last two boxes of a run so the opponent has to open the next one.
            case doubleCross
            /// Every line gives boxes away; this one gives the fewest.
            case fewest(boxes: Int)
            /// Gives boxes away on purpose (more than the minimum, or while safe lines remain)
            /// to come out ahead later.
            case sacrifice(boxes: Int)
        }

        public let line: Line
        public let kind: Kind

        public var title: String {
            switch kind {
            case .take(let n): n == 2 ? "Take these two boxes" : "Take this box"
            case .safe: "Safe line"
            case .doubleCross: "Keep control"
            case .fewest: "Smallest giveaway"
            case .sacrifice: "Sacrifice to win later"
            }
        }

        public var explanation: String {
            switch kind {
            case .take: "It completes a box, so you claim it and move again."
            case .safe: "It doesn't give away a box."
            case .doubleCross:
                "Leave the last two boxes to keep control: your opponent takes them, then has to open the next chain for you."
            case .fewest(let n):
                "Every line gives boxes away — this one gives the fewest (\(n == 1 ? "one box" : "\(n) boxes"))."
            case .sacrifice(let n):
                "Give away \(n == 1 ? "one box" : "\(n) boxes") now so your opponent has to open the long chains later."
            }
        }
    }
}

extension DotsAndBoxes.AI {
    /// The Hard computer's choice for the player to move, explained. Nil when the game is over.
    public static func hint(for game: DotsAndBoxes.Game, rng: inout SeededRandom) -> DotsAndBoxes.Hint? {
        guard !game.isOver else { return nil }
        let g = DotsAndBoxes.Geometry(rows: game.rows, cols: game.cols)
        let p = DotsAndBoxes.Bits(game)
        let edge = hardMove(g, p, &rng)
        return DotsAndBoxes.Hint(line: game.line(at: edge), kind: classify(edge, g, p))
    }

    public static func hint(for game: DotsAndBoxes.Game, seed: UInt64) -> DotsAndBoxes.Hint? {
        var rng = SeededRandom(seed: seed)
        return hint(for: game, rng: &rng)
    }

    static func classify(_ edge: Int, _ g: DotsAndBoxes.Geometry, _ p: DotsAndBoxes.Bits) -> DotsAndBoxes.Hint.Kind {
        let (q, completed) = g.apply(edge, p)
        if completed > 0 { return .take(boxes: completed) }
        // A box was there for the taking but this line leaves it: that's the double-cross.
        if !g.capturable(p).isEmpty { return .doubleCross }
        if g.isSafe(edge, p) { return .safe }
        let given = greedyCaptureCount(g, q)
        let safeRemain = !g.safeEdges(p).isEmpty
        let fewest = g.undrawn(p).map { greedyCaptureCount(g, g.apply($0, p).0) }.min() ?? given
        return !safeRemain && given <= fewest ? .fewest(boxes: given) : .sacrifice(boxes: given)
    }
}
