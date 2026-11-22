extension Chess.Position {
    /// Standard Algebraic Notation for a legal move in this position, e.g. "Nbd7", "exd6", "e8=Q+", "O-O#".
    public func san(_ move: Chess.Move) -> String {
        san(move, legal: legalMoves())
    }

    func san(_ move: Chess.Move, legal: [Chess.Move]) -> String {
        var s: String
        guard let piece = piece(at: move.from) else { return move.uci }
        if move.isCastle {
            s = move.to.file == 6 ? "O-O" : "O-O-O"
        } else if piece.kind == .pawn {
            s = move.isCapture ? move.from.fileLetter + "x" + move.to.name : move.to.name
            if let promo = move.promotion { s += "=" + String(promo.letter) }
        } else {
            s = String(piece.kind.letter)
            let rivals = legal.filter {
                $0.to == move.to && $0.from != move.from && self.piece(at: $0.from) == piece
            }
            if !rivals.isEmpty {
                let sameFile = rivals.contains { $0.from.file == move.from.file }
                let sameRank = rivals.contains { $0.from.rank == move.from.rank }
                if !sameFile {
                    s += move.from.fileLetter
                } else if !sameRank {
                    s += String(move.from.rank + 1)
                } else {
                    s += move.from.name
                }
            }
            if move.isCapture { s += "x" }
            s += move.to.name
        }
        let next = applying(move)
        if next.isInCheck {
            s += next.hasLegalMove ? "+" : "#"
        }
        return s
    }

    /// Parses SAN (tolerates missing/extra "+", "#", "!", "?" and "0-0" castling).
    public func move(san text: String) -> Chess.Move? {
        func normalize(_ s: String) -> String {
            s.replacingZeroCastling().filter { !"+#!?".contains($0) }
        }
        let target = normalize(text)
        let legal = legalMoves()
        return legal.first { normalize(san($0, legal: legal)) == target }
    }
}

private extension String {
    func replacingZeroCastling() -> String {
        if hasPrefix("0-0-0") { return "O-O-O" + dropFirst(5) }
        if hasPrefix("0-0") { return "O-O" + dropFirst(3) }
        return self
    }
}

extension Chess {
    /// How a game ended.
    public enum Outcome: Equatable, Codable, Sendable {
        case checkmate(winner: Side)
        case resignation(winner: Side)
        case stalemate
        case fiftyMoveRule
        case threefoldRepetition
        case insufficientMaterial

        public var winner: Side? {
            switch self {
            case .checkmate(let w), .resignation(let w): w
            default: nil
            }
        }

        public var isDraw: Bool { winner == nil }

        /// Short human-readable reason.
        public var reason: String {
            switch self {
            case .checkmate: "Checkmate"
            case .resignation(let w): "\(w.opponent.name) resigned"
            case .stalemate: "Stalemate"
            case .fiftyMoveRule: "50-move rule"
            case .threefoldRepetition: "Threefold repetition"
            case .insufficientMaterial: "Insufficient material"
            }
        }
    }

    /// A game record: start position, moves played (with SAN), and the resulting positions.
    /// Encodes compactly as the start FEN plus UCI moves.
    public struct Game: Equatable, Sendable, Codable {
        public let startFEN: String
        public private(set) var moves: [Move] = []
        public private(set) var sanMoves: [String] = []
        /// positions[0] is the start; positions[i] is the position after `i` moves.
        public private(set) var positions: [Position]
        /// The side that resigned, if any.
        public private(set) var resigned: Side?

        public init(position: Position = .start) {
            startFEN = position.fen
            positions = [position]
        }

        public init(fen: String) throws {
            self.init(position: try Position(fen: fen))
        }

        public var position: Position { positions[positions.count - 1] }
        public var sideToMove: Side { position.sideToMove }
        public var lastMove: Move? { moves.last }
        public var isOver: Bool { outcome != nil }

        public var outcome: Outcome? {
            if let resigned { return .resignation(winner: resigned.opponent) }
            let p = position
            if !p.hasLegalMove {
                return p.isInCheck ? .checkmate(winner: p.sideToMove.opponent) : .stalemate
            }
            if p.hasInsufficientMaterial { return .insufficientMaterial }
            if p.halfmoveClock >= 100 { return .fiftyMoveRule }
            if repetitionCount >= 3 { return .threefoldRepetition }
            return nil
        }

        /// How many times the current position has occurred (same placement, side, rights, en passant).
        public var repetitionCount: Int {
            let p = position
            var count = 1
            var i = positions.count - 3
            let lowest = max(0, positions.count - 1 - p.halfmoveClock)
            while i >= lowest {
                if positions[i].hash == p.hash { count += 1 }
                i -= 2
            }
            return count
        }

        /// Hashes of the positions since the last irreversible move (for search repetition detection).
        public var recentHashes: [UInt64] {
            let start = max(0, positions.count - 1 - position.halfmoveClock)
            return positions[start...].map(\.hash)
        }

        /// Plays a move if legal. Returns false (and does nothing) otherwise or when the game is over.
        @discardableResult
        public mutating func play(_ move: Move) -> Bool {
            guard resigned == nil else { return false }
            let legal = position.legalMoves()
            guard legal.contains(move), outcome == nil else { return false }
            sanMoves.append(position.san(move, legal: legal))
            moves.append(move)
            positions.append(position.applying(move))
            return true
        }

        @discardableResult
        public mutating func play(san: String) -> Bool {
            guard let m = position.move(san: san) else { return false }
            return play(m)
        }

        @discardableResult
        public mutating func play(uci: String) -> Bool {
            guard let m = position.move(uci: uci) else { return false }
            return play(m)
        }

        /// Takes back the last move (also clears a resignation first).
        @discardableResult
        public mutating func undo() -> Move? {
            if resigned != nil {
                resigned = nil
                return nil
            }
            guard let m = moves.popLast() else { return nil }
            sanMoves.removeLast()
            positions.removeLast()
            return m
        }

        public mutating func resign(_ side: Side) {
            guard outcome == nil else { return }
            resigned = side
        }

        /// Pieces captured *by* `side`, in capture order.
        public func captured(by side: Side) -> [PieceKind] {
            var result: [PieceKind] = []
            for (i, m) in moves.enumerated() where m.isCapture {
                let before = positions[i]
                guard before.sideToMove == side else { continue }
                if m.isEnPassant {
                    result.append(.pawn)
                } else if let p = before.piece(at: m.to) {
                    result.append(p.kind)
                }
            }
            return result
        }

        /// Material balance in pawns from White's point of view (promotions included).
        public var materialBalance: Int {
            position.pieces.reduce(0) { sum, entry in
                sum + (entry.piece.side == .white ? 1 : -1) * entry.piece.kind.points
            }
        }

        /// Move list as "1. e4 e5 2. Nf3 ..." (numbering respects a black-to-move start).
        public var pgnMoveText: String {
            var parts: [String] = []
            for (i, san) in sanMoves.enumerated() {
                let p = positions[i]
                if p.sideToMove == .white {
                    parts.append("\(p.fullmoveNumber). \(san)")
                } else if i == 0 {
                    parts.append("\(p.fullmoveNumber)... \(san)")
                } else {
                    parts.append(san)
                }
            }
            return parts.joined(separator: " ")
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey { case startFEN, moves, resigned }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(startFEN, forKey: .startFEN)
            try c.encode(moves.map(\.uci), forKey: .moves)
            try c.encodeIfPresent(resigned, forKey: .resigned)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let fen = try c.decode(String.self, forKey: .startFEN)
            try self.init(fen: fen)
            for uci in try c.decode([String].self, forKey: .moves) {
                guard play(uci: uci) else {
                    throw DecodingError.dataCorruptedError(forKey: .moves, in: c, debugDescription: "illegal move \(uci)")
                }
            }
            resigned = try c.decodeIfPresent(Side.self, forKey: .resigned)
        }

        public static func == (a: Game, b: Game) -> Bool {
            a.startFEN == b.startFEN && a.moves == b.moves && a.resigned == b.resigned
        }
    }
}
