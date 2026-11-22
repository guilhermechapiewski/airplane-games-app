extension Solitaire {
    /// A bounded depth-first Klondike solver, used to deal games that are known to be winnable.
    ///
    /// It searches until every tableau card is face up (and, in Draw 3, the stock and
    /// waste are empty) — from there a game can always be finished by repeatedly
    /// playing the lowest card to its foundation. Safe foundation plays are made
    /// automatically and visited positions are remembered, which keeps the search
    /// small. A `false` result means "not proven within the budget", not "unwinnable".
    public enum Solver {
        public struct Result: Sendable {
            public var solved: Bool
            /// Moves from the starting position to the solved position (when `solved`).
            public var moves: [Move]
            public var nodes: Int
        }

        public static func isSolved(_ state: State) -> Bool {
            guard state.allFaceUp else { return false }
            return state.drawMode == .draw1 || (state.stock.isEmpty && state.waste.isEmpty)
        }

        public static func solve(_ start: State, nodeBudget: Int = 50_000) -> Result {
            struct Frame {
                var state: State
                var candidates: [Move]
                var next = 0
                var applied: Int
            }
            var root = start
            var path = playSafeMoves(&root)
            if isSolved(root) { return Result(solved: true, moves: path, nodes: 0) }

            var visited: Set<UInt64> = [key(root)]
            var stack = [Frame(state: root, candidates: candidates(root), applied: path.count)]
            var nodes = 0

            while let frame = stack.last {
                if nodes >= nodeBudget { return Result(solved: false, moves: [], nodes: nodes) }
                guard frame.next < frame.candidates.count else {
                    stack.removeLast()
                    path.removeLast(frame.applied)
                    continue
                }
                let move = frame.candidates[frame.next]
                stack[stack.count - 1].next += 1
                var state = frame.state
                guard state.apply(move) != nil else { continue }
                nodes += 1
                let forced = playSafeMoves(&state)
                if isSolved(state) {
                    return Result(solved: true, moves: path + [move] + forced, nodes: nodes)
                }
                guard visited.insert(key(state)).inserted else { continue }
                path.append(move)
                path.append(contentsOf: forced)
                stack.append(Frame(state: state, candidates: candidates(state), applied: 1 + forced.count))
            }
            return Result(solved: false, moves: [], nodes: nodes)
        }

        /// Plays foundation moves that can never hurt: Aces and Twos, or a card whose
        /// opposite-color predecessors are already on the foundations.
        static func playSafeMoves(_ state: inout State) -> [Move] {
            var played: [Move] = []
            var progress = true
            while progress {
                progress = false
                var sources: [Pile] = (0..<7).map(Pile.tableau)
                sources.append(.waste)
                for pile in sources {
                    guard let card = state.top(of: pile), isSafe(card, in: state),
                          let f = state.foundationTarget(for: card) else { continue }
                    let move = Move(from: pile, to: .foundation(f))
                    if state.apply(move) != nil {
                        played.append(move)
                        progress = true
                    }
                }
            }
            return played
        }

        static func isSafe(_ card: Card, in state: State) -> Bool {
            if card.rank <= 2 { return true }
            var height = [Int](repeating: 0, count: 4)
            for pile in state.foundations { if let top = pile.last { height[top.suit.rawValue] = top.rank } }
            return Suit.allCases.filter { $0.isRed != card.isRed }.allSatisfy { height[$0.rawValue] >= card.rank - 1 }
        }

        /// Candidate moves in the order they're explored.
        static func candidates(_ s: State) -> [Move] {
            var moves: [Move] = []
            // 1. Foundation plays.
            for t in 0..<7 {
                if let top = s.tableau[t].top, let f = s.foundationTarget(for: top) {
                    moves.append(Move(from: .tableau(t), to: .foundation(f)))
                }
            }
            if let card = s.waste.last, let f = s.foundationTarget(for: card) {
                moves.append(Move(from: .waste, to: .foundation(f)))
            }
            // 2. Moves that reveal a hidden card, deepest columns first.
            let byDepth = (0..<7).sorted { s.tableau[$0].faceDownCount > s.tableau[$1].faceDownCount }
            let firstEmpty = s.tableau.firstIndex(where: \.isEmpty)
            for t in byDepth where s.tableau[t].faceDownCount > 0 {
                let column = s.tableau[t]
                let lead = column.cards[column.faceDownCount]
                for d in 0..<7 where d != t && s.canPlace(lead, onTableau: d) {
                    if s.tableau[d].isEmpty && d != firstEmpty { continue }
                    moves.append(Move(from: .tableau(t), to: .tableau(d), count: column.faceUpCount))
                }
            }
            // 3. Waste to tableau.
            if let card = s.waste.last {
                for d in 0..<7 where s.canPlace(card, onTableau: d) {
                    if s.tableau[d].isEmpty && d != firstEmpty { continue }
                    moves.append(Move(from: .waste, to: .tableau(d)))
                }
            }
            // 4. Partial runs that free a card for its foundation.
            for t in 0..<7 where s.tableau[t].faceUpCount > 1 {
                let column = s.tableau[t]
                for i in (column.faceDownCount + 1)..<column.cards.count where s.foundationTarget(for: column.cards[i - 1]) != nil {
                    for d in 0..<7 where d != t && !s.tableau[d].isEmpty && s.canPlace(column.cards[i], onTableau: d) {
                        moves.append(Move(from: .tableau(t), to: .tableau(d), count: column.cards.count - i))
                    }
                }
            }
            // 5. Emptying a column (only worth it if a King could use the space).
            let kingAvailable = s.tableau.contains { $0.faceDownCount > 0 && $0.cards[$0.faceDownCount].isKing }
                || s.stock.contains(where: \.isKing) || s.waste.contains(where: \.isKing)
            if kingAvailable {
                for t in 0..<7 where s.tableau[t].faceDownCount == 0 && !s.tableau[t].isEmpty && !s.tableau[t].cards[0].isKing {
                    let lead = s.tableau[t].cards[0]
                    for d in 0..<7 where d != t && !s.tableau[d].isEmpty && s.canPlace(lead, onTableau: d) {
                        moves.append(Move(from: .tableau(t), to: .tableau(d), count: s.tableau[t].cards.count))
                    }
                }
            }
            // 6. Foundation back down to the tableau (occasionally needed to park a card).
            for f in 0..<4 {
                guard let card = s.foundations[f].last, card.rank > 2 else { continue }
                for d in 0..<7 where !s.tableau[d].isEmpty && s.canPlace(card, onTableau: d) {
                    moves.append(Move(from: .foundation(f), to: .tableau(d)))
                }
            }
            // 7. The stock.
            if !s.stock.isEmpty { moves.append(.draw) } else if !s.waste.isEmpty { moves.append(.recycle) }
            return moves
        }

        /// A 64-bit FNV-1a fingerprint of the card layout (ignores score, move count and fan).
        static func key(_ s: State) -> UInt64 {
            var h: UInt64 = 0xCBF2_9CE4_8422_2325
            func mix(_ v: Int) {
                h ^= UInt64(truncatingIfNeeded: v)
                h &*= 0x0000_0100_0000_01B3
            }
            for c in s.stock { mix(c.id) }
            mix(200)
            for c in s.waste { mix(c.id) }
            mix(201)
            for column in s.tableau {
                mix(100 + column.faceDownCount)
                for c in column.cards { mix(c.id) }
                mix(202)
            }
            // Foundations are interchangeable slots; record the height of each suit.
            var height = [Int](repeating: 0, count: 4)
            for pile in s.foundations { if let top = pile.last { height[top.suit.rawValue] = top.rank } }
            for v in height { mix(v) }
            return h
        }
    }

    /// The result of looking for a winnable deal.
    public struct Deal: Sendable {
        public var state: State
        /// The seed that produced `state`.
        public var seed: UInt64
        /// The solver proved this deal can be won.
        public var provenWinnable: Bool
    }

    /// Deals games from seeds derived from `seed` until the solver proves one winnable.
    /// Falls back to the first deal if none is proven within `maxAttempts` or before
    /// `shouldContinue` returns `false` (use it for a deadline or cancellation).
    public static func winnableDeal(drawMode: DrawMode, seed: UInt64, maxAttempts: Int = 40,
                                    nodeBudget: Int = 20_000,
                                    shouldContinue: () -> Bool = { true }) -> Deal {
        var rng = SeededRandom(seed: seed)
        var first: Deal?
        for _ in 0..<max(1, maxAttempts) {
            let dealSeed = rng.next()
            let state = State.deal(drawMode: drawMode, seed: dealSeed)
            if first == nil { first = Deal(state: state, seed: dealSeed, provenWinnable: false) }
            if Solver.solve(state, nodeBudget: nodeBudget).solved {
                return Deal(state: state, seed: dealSeed, provenWinnable: true)
            }
            if !shouldContinue() { break }
        }
        return first!
    }
}
