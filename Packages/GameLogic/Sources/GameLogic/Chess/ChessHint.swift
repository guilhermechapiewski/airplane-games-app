extension Chess {
    /// A suggested move for the side to move, with a short reason when one is cheap to name.
    public struct Hint: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case checkmate
            /// A forced mate in this many moves (2 or more).
            case forcesMate(in: Int)
            case promotes(PieceKind)
            case captures(PieceKind, givesCheck: Bool)
            /// The moving piece was attacked (and not safely defended) and this move saves it.
            case escapes(PieceKind)
            case givesCheck
            case castles
            case develops(PieceKind)
            case takesCenter
        }

        public let move: Move
        public let reason: Reason?
        /// The moving piece.
        public let piece: Piece

        /// One short sentence explaining the move, or nil when there is nothing simple to say.
        public var explanation: String? {
            guard let reason else { return nil }
            switch reason {
            case .checkmate: return "Checkmate!"
            case .forcesMate(let n): return "Forces checkmate in \(n) moves."
            case .promotes(let kind): return "Promotes the pawn to a \(kind.name)."
            case .captures(let kind, let check):
                return "Captures a \(kind.name)" + (check ? " with check." : ".")
            case .escapes(let kind): return "Gets your \(kind.name) out of danger."
            case .givesCheck: return "Gives check."
            case .castles: return "Castles: tucks your king away and brings a rook into play."
            case .develops(let kind): return "Develops a \(kind.name) toward the center."
            case .takesCenter: return "Claims space in the center."
            }
        }

        /// "knight from g1 to f3", "castle kingside".
        public var spokenMove: String {
            if move.isCastle { return move.to.file == 6 ? "castle kingside" : "castle queenside" }
            var text = "\(piece.kind.name) from \(move.from.name) to \(move.to.name)"
            if let promo = move.promotion { text += ", promoting to \(promo.name)" }
            return text
        }
    }
}

extension Chess.Engine {
    /// Suggests a move for the side to move using the strongest search, capped at `timeLimit`
    /// seconds. Returns nil when there is no legal move or the search was cancelled.
    public static func hint(for game: Chess.Game, timeLimit: Double = 0.8,
                            shouldStop: @escaping @Sendable () -> Bool = { false }) -> Chess.Hint? {
        let position = game.position
        let legal = position.legalMoves()
        guard !legal.isEmpty, !game.isOver else { return nil }

        // A mate in one is always the hint (and costs almost nothing to find).
        if let mate = legal.first(where: { m in
            let next = position.applying(m)
            return next.isInCheck && !next.hasLegalMove
        }) {
            return makeHint(mate, in: position, mateIn: 1)
        }

        let history = game.recentHashes.dropLast().map { $0 }
        let result = search(position, history: history, maxDepth: Chess.Level.master.settings.depth,
                            timeLimit: timeLimit, shouldStop: shouldStop)
        if Task.isCancelled || shouldStop() { return nil }
        guard let move = result.move ?? legal.first else { return nil }
        let mateIn = result.mateIn.flatMap { $0 > 0 ? $0 : nil }
        return makeHint(move, in: position, mateIn: mateIn)
    }

    static func makeHint(_ move: Chess.Move, in position: Chess.Position, mateIn: Int?) -> Chess.Hint {
        let piece = position.piece(at: move.from) ?? Chess.Piece(position.sideToMove, .pawn)
        return Chess.Hint(move: move, reason: reason(for: move, piece: piece, in: position, mateIn: mateIn), piece: piece)
    }

    static func reason(for move: Chess.Move, piece: Chess.Piece, in position: Chess.Position, mateIn: Int?) -> Chess.Hint.Reason? {
        let after = position.applying(move)
        let check = after.isInCheck
        if check && !after.hasLegalMove { return .checkmate }
        if let mateIn, mateIn >= 2 { return .forcesMate(in: mateIn) }
        if let promo = move.promotion { return .promotes(promo) }
        if move.isCapture {
            let victim = move.isEnPassant ? .pawn : position.piece(at: move.to)?.kind ?? .pawn
            return .captures(victim, givesCheck: check)
        }
        if piece.kind != .pawn && piece.kind != .king
            && isThreatened(move.from, in: position)
            && !isThreatened(move.to, afterMove: after) {
            return .escapes(piece.kind)
        }
        if check { return .givesCheck }
        if move.isCastle { return .castles }
        if position.fullmoveNumber <= 12 {
            let homeRank = piece.side == .white ? 0 : 7
            if (piece.kind == .knight || piece.kind == .bishop) && move.from.rank == homeRank {
                return .develops(piece.kind)
            }
            if piece.kind == .pawn && [3, 4].contains(move.to.file) && [3, 4].contains(move.to.rank) {
                return .takesCenter
            }
        }
        return nil
    }

    /// Whether the side to move's piece on `square` can be won: attacked and either undefended
    /// or attacked by something cheaper.
    static func isThreatened(_ square: Chess.Square, in position: Chess.Position) -> Bool {
        guard let piece = position.piece(at: square), piece.side == position.sideToMove else { return false }
        var swapped = position
        _ = swapped.makeNull()
        let attackers = cheapestAttacker(of: square, in: swapped)
        guard let attacker = attackers else { return false }
        let defended = position.isSquareAttacked(square, by: piece.side)
        return !defended || value(attacker) < value(piece.kind)
    }

    /// Same question for the piece that just moved to `square` (the opponent is now to move).
    static func isThreatened(_ square: Chess.Square, afterMove position: Chess.Position) -> Bool {
        guard let piece = position.piece(at: square), let attacker = cheapestAttacker(of: square, in: position) else {
            return false
        }
        let defended = position.isSquareAttacked(square, by: piece.side)
        return !defended || value(attacker) < value(piece.kind)
    }

    /// The least valuable piece of the side to move that can capture on `square` (ignores pins).
    private static func cheapestAttacker(of square: Chess.Square, in position: Chess.Position) -> Chess.PieceKind? {
        var moves: [Chess.Move] = []
        position.generatePseudoLegal(into: &moves, capturesOnly: true)
        return moves
            .filter { $0.to == square && !$0.isEnPassant }
            .compactMap { position.piece(at: $0.from)?.kind }
            .min { value($0) < value($1) }
    }

    /// Exchange value: a king can only capture undefended pieces, so it counts as the most valuable.
    private static func value(_ kind: Chess.PieceKind) -> Int {
        kind == .king ? 100 : kind.points
    }
}
