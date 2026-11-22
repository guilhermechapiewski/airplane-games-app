extension Chess {
    /// Computer opponent strength.
    public enum Level: Int, CaseIterable, Codable, Sendable, Identifiable {
        case beginner = 1, casual, intermediate, advanced, master

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .beginner: "Beginner"
            case .casual: "Casual"
            case .intermediate: "Intermediate"
            case .advanced: "Advanced"
            case .master: "Master"
            }
        }

        public var subtitle: String {
            switch self {
            case .beginner: "Learning the moves"
            case .casual: "Relaxed, makes mistakes"
            case .intermediate: "Solid club player"
            case .advanced: "Sharp tactics"
            case .master: "Thinks deeply"
            }
        }

        struct Settings {
            let depth: Int
            /// Seconds; nil = depth-limited only.
            let time: Double?
            /// Uniform random noise (± centipawns) added to root move scores.
            let noise: Int
            /// Chance of playing a random legal move instead.
            let blunder: Double
        }

        var settings: Settings {
            switch self {
            case .beginner: Settings(depth: 1, time: nil, noise: 240, blunder: 0.18)
            case .casual: Settings(depth: 2, time: nil, noise: 110, blunder: 0.07)
            case .intermediate: Settings(depth: 3, time: nil, noise: 35, blunder: 0.02)
            case .advanced: Settings(depth: 5, time: 0.8, noise: 0, blunder: 0)
            case .master: Settings(depth: 32, time: 1.5, noise: 0, blunder: 0)
            }
        }
    }

    public enum Engine {
        public static let mateScore = 30_000

        public struct Result: Sendable {
            public let move: Move?
            /// Score in centipawns from the side to move's point of view.
            public let score: Int
            /// Deepest fully completed iteration.
            public let depth: Int
            public let nodes: Int

            /// Moves to mate (positive: side to move mates; negative: gets mated), if a mate was found.
            public var mateIn: Int? {
                guard abs(score) >= mateScore - 200 else { return nil }
                let plies = mateScore - abs(score)
                return score > 0 ? (plies + 1) / 2 : -(plies + 1) / 2
            }
        }

        /// Iterative-deepening alpha-beta search.
        /// - Parameters:
        ///   - history: hashes of earlier positions since the last irreversible move (repetition detection).
        ///   - shouldStop: polled periodically; the search also stops when its task is cancelled.
        public static func search(_ position: Position,
                                  history: [UInt64] = [],
                                  maxDepth: Int,
                                  timeLimit: Double? = nil,
                                  nodeLimit: Int? = nil,
                                  shouldStop: @escaping @Sendable () -> Bool = { false }) -> Result {
            let searcher = Searcher(position: position, history: history,
                                    timeLimit: timeLimit, nodeLimit: nodeLimit, shouldStop: shouldStop)
            return searcher.iterativeDeepening(maxDepth: maxDepth)
        }

        /// Picks a move for the side to move at the given level. Returns nil when there is no
        /// legal move or the search was cancelled before any move was found.
        public static func chooseMove(for game: Game, level: Level, seed: UInt64? = nil,
                                      shouldStop: @escaping @Sendable () -> Bool = { false }) -> Move? {
            let position = game.position
            let legal = position.legalMoves()
            guard !legal.isEmpty else { return nil }
            if legal.count == 1 { return legal[0] }
            var rng = seed.map(SeededRandom.init(seed:)) ?? SeededRandom()
            let s = level.settings
            let history = game.recentHashes.dropLast().map { $0 }

            if s.noise == 0 && s.blunder == 0 {
                return search(position, history: history, maxDepth: s.depth, timeLimit: s.time,
                              shouldStop: shouldStop).move
            }

            if Double(rng.next() % 10_000) / 10_000 < s.blunder {
                // A "human" slip: a random move, but never one that hangs mate in one.
                let safe = legal.filter { m in
                    let next = position.applying(m)
                    return !next.legalMoves().contains { reply in
                        let after = next.applying(reply)
                        return after.isInCheck && !after.hasLegalMove
                    }
                }
                let pool = safe.isEmpty ? legal : safe
                return pool[Int(rng.next() % UInt64(pool.count))]
            }

            let searcher = Searcher(position: position, history: history, timeLimit: s.time,
                                    nodeLimit: nil, shouldStop: shouldStop)
            let scored = searcher.scoreRootMoves(legal, depth: s.depth)
            if searcher.stopped { return nil }
            var best: Move?
            var bestScore = Int.min
            for (move, score) in scored {
                var noisy = score
                if abs(score) < mateScore - 200 {
                    noisy += Int(rng.next() % UInt64(2 * s.noise + 1)) - s.noise
                }
                if noisy > bestScore {
                    bestScore = noisy
                    best = move
                }
            }
            return best
        }
    }

    /// Transposition table entry.
    struct TTEntry {
        var key: UInt64 = 0
        var move: UInt32 = 0
        var score: Int16 = 0
        var depth: Int8 = -1
        var flag: UInt8 = 0

        static let exact: UInt8 = 0, lower: UInt8 = 1, upper: UInt8 = 2
    }

    /// One search; owns its position copy and all scratch buffers (no allocation in the tree).
    final class Searcher {
        static let maxPly = 64
        static let infinity = 32_000
        static let mate = Engine.mateScore

        var pos: Position
        private var path: [UInt64]
        private var tt: [TTEntry]
        private let ttMask: Int
        private var killers: [UInt32]
        private var historyScores: [Int32]
        private var moveBuffers: [[Move]]
        private var scoreBuffers: [[Int32]]
        private(set) var nodes = 0
        private(set) var stopped = false
        private var canTimeOut = false
        private let deadline: ContinuousClock.Instant?
        private let nodeLimit: Int
        private let shouldStop: @Sendable () -> Bool
        private var rootBest: Move?
        private var rootBestScore = 0

        init(position: Position, history: [UInt64], timeLimit: Double?, nodeLimit: Int?,
             shouldStop: @escaping @Sendable () -> Bool, ttBits: Int = 18) {
            pos = position
            path = history + [position.hash]
            path.reserveCapacity(path.count + Self.maxPly + 8)
            tt = [TTEntry](repeating: TTEntry(), count: 1 << ttBits)
            ttMask = (1 << ttBits) - 1
            killers = [UInt32](repeating: 0, count: Self.maxPly * 2)
            historyScores = [Int32](repeating: 0, count: 2 * 128 * 128)
            moveBuffers = (0..<(Self.maxPly + 1)).map { _ in
                var a: [Move] = []
                a.reserveCapacity(96)
                return a
            }
            scoreBuffers = (0..<(Self.maxPly + 1)).map { _ in
                var a: [Int32] = []
                a.reserveCapacity(96)
                return a
            }
            deadline = timeLimit.map { ContinuousClock.now + .milliseconds(Int($0 * 1000)) }
            self.nodeLimit = nodeLimit ?? Int.max
            self.shouldStop = shouldStop
        }

        // MARK: Drivers

        func iterativeDeepening(maxDepth: Int) -> Engine.Result {
            var best: Move?
            var bestScore = 0
            var completed = 0
            let start = ContinuousClock.now
            for depth in 1...max(1, min(maxDepth, Self.maxPly - 2)) {
                rootBest = nil
                let score = negamax(depth, 0, -Self.infinity, Self.infinity, false)
                if stopped {
                    // A partial iteration searched the previous best first, so any improvement is trustworthy.
                    if let partial = rootBest {
                        best = partial
                        bestScore = rootBestScore
                    }
                    break
                }
                best = rootBest ?? best
                bestScore = score
                completed = depth
                canTimeOut = true
                if abs(score) >= Self.mate - depth { break } // forced mate found
                if let deadline {
                    // Don't start an iteration we are unlikely to finish.
                    let elapsed = ContinuousClock.now - start
                    let remaining = deadline - ContinuousClock.now
                    if remaining < elapsed * 2 { break }
                }
            }
            return Engine.Result(move: best, score: bestScore, depth: completed, nodes: nodes)
        }

        /// Exact (full-window) scores for each root move at a fixed depth.
        func scoreRootMoves(_ moves: [Move], depth: Int) -> [(Move, Int)] {
            var result: [(Move, Int)] = []
            for m in moves {
                let u = pos.make(m)
                path.append(pos.hash)
                let s = -negamax(depth - 1, 1, -Self.infinity, Self.infinity, true)
                path.removeLast()
                pos.unmake(m, u)
                if stopped { return result }
                result.append((m, s))
            }
            return result
        }

        // MARK: Search

        @inline(__always) private func checkStop() -> Bool {
            if stopped { return true }
            if nodes & 1023 == 0 {
                if shouldStop() || Task.isCancelled {
                    stopped = true
                } else if canTimeOut {
                    if nodes >= nodeLimit { stopped = true }
                    if let deadline, ContinuousClock.now >= deadline { stopped = true }
                }
            }
            return stopped
        }

        private func isRepetition() -> Bool {
            let n = path.count
            let current = path[n - 1]
            let lowest = max(0, n - 1 - pos.halfmoveClock)
            var i = n - 3
            while i >= lowest {
                if path[i] == current { return true }
                i -= 2
            }
            return false
        }

        private func negamax(_ depthIn: Int, _ ply: Int, _ alphaIn: Int, _ betaIn: Int, _ allowNull: Bool) -> Int {
            if checkStop() { return 0 }
            nodes += 1
            var alpha = alphaIn
            var beta = betaIn
            if ply > 0 {
                if pos.halfmoveClock >= 100 || isRepetition() { return 0 }
                // Mate distance pruning.
                alpha = max(alpha, -Self.mate + ply)
                beta = min(beta, Self.mate - ply - 1)
                if alpha >= beta { return alpha }
            }
            if ply >= Self.maxPly - 2 { return pos.evaluate() }
            let pvNode = beta - alpha > 1
            let inCheck = pos.isInCheck
            var depth = depthIn
            if inCheck { depth += 1 }
            if depth <= 0 { return quiesce(ply, alpha, beta) }

            let ttIndex = Int(truncatingIfNeeded: pos.hash) & ttMask
            var ttMove: UInt32 = 0
            let entry = tt[ttIndex]
            if entry.key == pos.hash {
                ttMove = entry.move
                if !pvNode && Int(entry.depth) >= depth {
                    let s = scoreFromTT(Int(entry.score), ply)
                    switch entry.flag {
                    case TTEntry.exact: return s
                    case TTEntry.lower where s >= beta: return s
                    case TTEntry.upper where s <= alpha: return s
                    default: break
                    }
                }
            }

            // Null-move pruning (skipped in pawn endings to avoid zugzwang errors).
            if allowNull && !pvNode && !inCheck && depth >= 3 && pos.sideHasNonPawnMaterial && pos.evaluate() >= beta {
                let u = pos.makeNull()
                path.append(pos.hash)
                let r = depth >= 6 ? 3 : 2
                let s = -negamax(depth - 1 - r, ply + 1, -beta, -beta + 1, false)
                path.removeLast()
                pos.unmakeNull(u)
                if stopped { return 0 }
                if s >= beta { return s >= Self.mate - Self.maxPly ? beta : s }
            }

            generateAndScore(ply, capturesOnly: false, ttMove: ttMove)
            let count = moveBuffers[ply].count
            let k1 = killers[ply * 2], k2 = killers[ply * 2 + 1]
            let sideIndex = pos.sideToMove.rawValue
            let originalAlpha = alpha
            var best = -Self.infinity
            var bestMove: UInt32 = 0
            var legal = 0

            for i in 0..<count {
                let m = pickNext(ply, i)
                let u = pos.make(m)
                if pos.leftKingInCheck {
                    pos.unmake(m, u)
                    continue
                }
                legal += 1
                path.append(pos.hash)
                var score: Int
                if legal == 1 {
                    score = -negamax(depth - 1, ply + 1, -beta, -alpha, true)
                } else {
                    var reduction = 0
                    if depth >= 3 && legal > 3 && !inCheck && m.isQuiet && m.raw != k1 && m.raw != k2 && !pos.isInCheck {
                        reduction = legal > 10 ? 2 : 1
                    }
                    score = -negamax(depth - 1 - reduction, ply + 1, -alpha - 1, -alpha, true)
                    if score > alpha && reduction > 0 && !stopped {
                        score = -negamax(depth - 1, ply + 1, -alpha - 1, -alpha, true)
                    }
                    if score > alpha && score < beta && !stopped {
                        score = -negamax(depth - 1, ply + 1, -beta, -alpha, true)
                    }
                }
                path.removeLast()
                pos.unmake(m, u)
                if stopped { return 0 }

                if score > best {
                    best = score
                    bestMove = m.raw
                    if ply == 0 {
                        rootBest = m
                        rootBestScore = score
                    }
                    if score > alpha {
                        alpha = score
                        if alpha >= beta {
                            if m.isQuiet {
                                if m.raw != k1 {
                                    killers[ply * 2 + 1] = k1
                                    killers[ply * 2] = m.raw
                                }
                                let h = sideIndex * 16384 + m.from88 * 128 + m.to88
                                historyScores[h] = min(historyScores[h] + Int32(depth * depth), 40_000)
                            }
                            break
                        }
                    }
                }
            }

            if legal == 0 { return inCheck ? -Self.mate + ply : 0 }

            let flag = best >= beta ? TTEntry.lower : (best > originalAlpha ? TTEntry.exact : TTEntry.upper)
            if entry.key != pos.hash || depth >= Int(entry.depth) || flag == TTEntry.exact {
                tt[ttIndex] = TTEntry(key: pos.hash, move: bestMove, score: Int16(scoreToTT(best, ply)),
                                      depth: Int8(min(depth, 127)), flag: flag)
            }
            return best
        }

        private func quiesce(_ ply: Int, _ alphaIn: Int, _ beta: Int) -> Int {
            if checkStop() { return 0 }
            nodes += 1
            let standPat = pos.evaluate()
            if ply >= Self.maxPly - 2 || standPat >= beta { return standPat }
            var alpha = max(alphaIn, standPat)
            var best = standPat

            generateAndScore(ply, capturesOnly: true, ttMove: 0)
            let count = moveBuffers[ply].count
            for i in 0..<count {
                let m = pickNext(ply, i)
                if m.promo == 0 {
                    // Delta pruning: even winning this piece cannot raise alpha.
                    let victim = m.isEnPassant ? 1 : Int(abs(pos.board[m.to88]))
                    if standPat + Evaluation.egValue[victim] + 200 <= alpha { continue }
                }
                let u = pos.make(m)
                if pos.leftKingInCheck {
                    pos.unmake(m, u)
                    continue
                }
                let s = -quiesce(ply + 1, -beta, -alpha)
                pos.unmake(m, u)
                if stopped { return 0 }
                if s > best {
                    best = s
                    if s > alpha {
                        alpha = s
                        if s >= beta { break }
                    }
                }
            }
            return best
        }

        // MARK: Move ordering

        private func generateAndScore(_ ply: Int, capturesOnly: Bool, ttMove: UInt32) {
            moveBuffers[ply].removeAll(keepingCapacity: true)
            pos.generatePseudoLegal(into: &moveBuffers[ply], capturesOnly: capturesOnly)
            scoreBuffers[ply].removeAll(keepingCapacity: true)
            let k1 = killers[ply * 2], k2 = killers[ply * 2 + 1]
            let sideIndex = pos.sideToMove.rawValue * 16384
            for m in moveBuffers[ply] {
                var score: Int32
                if m.raw == ttMove && ttMove != 0 {
                    score = 2_000_000
                } else if m.isCapture {
                    let victim = m.isEnPassant ? 1 : Int32(abs(pos.board[m.to88]))
                    let attacker = Int32(abs(pos.board[m.from88]))
                    score = 1_000_000 + victim * 100 - attacker
                    if m.promo == PieceKind.queen.rawValue { score += 900 }
                } else if m.promo != 0 {
                    score = m.promo == PieceKind.queen.rawValue ? 950_000 : 100
                } else if m.raw == k1 {
                    score = 900_000
                } else if m.raw == k2 {
                    score = 890_000
                } else {
                    score = historyScores[sideIndex + m.from88 * 128 + m.to88]
                }
                scoreBuffers[ply].append(score)
            }
        }

        /// Selection sort step: brings the best remaining move to index `i`.
        @inline(__always) private func pickNext(_ ply: Int, _ i: Int) -> Move {
            let count = scoreBuffers[ply].count
            var bestIndex = i
            var bestScore = scoreBuffers[ply][i]
            var j = i + 1
            while j < count {
                let s = scoreBuffers[ply][j]
                if s > bestScore {
                    bestScore = s
                    bestIndex = j
                }
                j += 1
            }
            if bestIndex != i {
                scoreBuffers[ply].swapAt(i, bestIndex)
                moveBuffers[ply].swapAt(i, bestIndex)
            }
            return moveBuffers[ply][i]
        }

        // Mate scores are stored relative to the node, not the root.
        private func scoreToTT(_ s: Int, _ ply: Int) -> Int {
            if s >= Self.mate - Self.maxPly { return s + ply }
            if s <= -Self.mate + Self.maxPly { return s - ply }
            return s
        }

        private func scoreFromTT(_ s: Int, _ ply: Int) -> Int {
            if s >= Self.mate - Self.maxPly { return s - ply }
            if s <= -Self.mate + Self.maxPly { return s + ply }
            return s
        }
    }
}
