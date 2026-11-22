extension Chess {
    /// Precomputed tables shared by move generation and hashing.
    enum Tables {
        static let knight = [33, 31, 18, 14, -33, -31, -18, -14]
        static let king = [1, -1, 16, -16, 15, 17, -15, -17]
        static let diagonal = [15, 17, -15, -17]
        static let orthogonal = [1, -1, 16, -16]

        /// Castling-rights mask applied for both the from and to square of every move.
        static let castleMask: [UInt8] = {
            var m = [UInt8](repeating: 0xF, count: 128)
            m[0] = 0xF & ~Position.whiteQueenside   // a1
            m[4] = 0xF & ~(Position.whiteKingside | Position.whiteQueenside) // e1
            m[7] = 0xF & ~Position.whiteKingside    // h1
            m[112] = 0xF & ~Position.blackQueenside // a8
            m[116] = 0xF & ~(Position.blackKingside | Position.blackQueenside) // e8
            m[119] = 0xF & ~Position.blackKingside  // h8
            return m
        }()

        /// Zobrist keys: [pieceIndex * 128 + sq88] for 12 piece types, then castling (16),
        /// en-passant file (8) and side to move.
        static let zobrist: [UInt64] = {
            var rng = SeededRandom(seed: 0xC0FF_EE15_DEAD_BEEF)
            return (0..<(12 * 128 + 16 + 8 + 1)).map { _ in rng.next() }
        }()
        static let zCastleBase = 12 * 128
        static let zEPBase = 12 * 128 + 16
        static let zSide = 12 * 128 + 16 + 8

        @inline(__always) static func pieceKey(_ code: Int8, _ sq: Int) -> UInt64 {
            let idx = code > 0 ? Int(code) - 1 : Int(-code) + 5
            return zobrist[idx * 128 + sq]
        }
    }

    /// Information needed to take back a move made with `make`.
    struct Undo {
        let captured: Int8
        let castling: UInt8
        let ep: Int
        let halfmove: Int
        let hash: UInt64
    }

    /// A complete chess position.
    public struct Position: Sendable, Equatable, Hashable {
        static let whiteKingside: UInt8 = 1
        static let whiteQueenside: UInt8 = 2
        static let blackKingside: UInt8 = 4
        static let blackQueenside: UInt8 = 8

        public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        // swiftlint:disable:next force_try
        public static let start = try! Position(fen: startFEN)

        var board: [Int8]
        public private(set) var sideToMove: Side
        var castling: UInt8
        /// En-passant target square (0x88) or -1. Only set when a capture is pseudo-legal.
        var ep: Int
        public private(set) var halfmoveClock: Int
        public private(set) var fullmoveNumber: Int
        var whiteKing: Int
        var blackKing: Int
        /// Zobrist hash, maintained incrementally.
        public private(set) var hash: UInt64

        // MARK: FEN

        public init(fen: String) throws {
            let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { throw FENError.invalid("expected at least 2 fields") }
            board = [Int8](repeating: 0, count: 128)
            let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: false)
            guard ranks.count == 8 else { throw FENError.invalid("expected 8 ranks") }
            var wk = -1, bk = -1
            for (i, row) in ranks.enumerated() {
                let rank = 7 - i
                var file = 0
                for ch in row {
                    if let d = ch.wholeNumberValue {
                        guard (1...8).contains(d) else { throw FENError.invalid("bad digit") }
                        file += d
                    } else {
                        guard file < 8, let kind = PieceKind(letter: ch) else { throw FENError.invalid("bad piece '\(ch)'") }
                        let piece = Piece(ch.isUppercase ? .white : .black, kind)
                        let sq = rank * 16 + file
                        board[sq] = piece.code
                        if kind == .king {
                            if piece.side == .white {
                                guard wk < 0 else { throw FENError.invalid("two white kings") }
                                wk = sq
                            } else {
                                guard bk < 0 else { throw FENError.invalid("two black kings") }
                                bk = sq
                            }
                        }
                        if kind == .pawn, rank == 0 || rank == 7 { throw FENError.invalid("pawn on back rank") }
                        file += 1
                    }
                    if file > 8 { throw FENError.invalid("rank too long") }
                }
                guard file == 8 else { throw FENError.invalid("rank too short") }
            }
            guard wk >= 0, bk >= 0 else { throw FENError.invalid("missing king") }
            whiteKing = wk
            blackKing = bk
            switch parts[1] {
            case "w": sideToMove = .white
            case "b": sideToMove = .black
            default: throw FENError.invalid("bad side to move")
            }
            castling = 0
            if parts.count > 2, parts[2] != "-" {
                for ch in parts[2] {
                    switch ch {
                    case "K": castling |= Self.whiteKingside
                    case "Q": castling |= Self.whiteQueenside
                    case "k": castling |= Self.blackKingside
                    case "q": castling |= Self.blackQueenside
                    default: throw FENError.invalid("bad castling field")
                    }
                }
            }
            // Drop rights that are impossible given the piece placement.
            if board[4] != 6 { castling &= ~(Self.whiteKingside | Self.whiteQueenside) }
            if board[7] != 4 { castling &= ~Self.whiteKingside }
            if board[0] != 4 { castling &= ~Self.whiteQueenside }
            if board[116] != -6 { castling &= ~(Self.blackKingside | Self.blackQueenside) }
            if board[119] != -4 { castling &= ~Self.blackKingside }
            if board[112] != -4 { castling &= ~Self.blackQueenside }
            ep = -1
            if parts.count > 3, parts[3] != "-" {
                guard let sq = Square(parts[3]) else { throw FENError.invalid("bad en passant square") }
                ep = sq.sq88
            }
            halfmoveClock = parts.count > 4 ? Int(parts[4]) ?? 0 : 0
            fullmoveNumber = parts.count > 5 ? max(1, Int(parts[5]) ?? 1) : 1
            hash = 0
            if ep >= 0, !epCapturePossible(ep) { ep = -1 }
            // The side not to move must not be in check.
            if isAttacked(sideToMove == .white ? bk : wk, by: sideToMove) {
                throw FENError.invalid("side not to move is in check")
            }
            hash = computeHash()
        }

        public var fen: String {
            var rows: [String] = []
            for rank in stride(from: 7, through: 0, by: -1) {
                var row = ""
                var empty = 0
                for file in 0..<8 {
                    if let p = Piece(code: board[rank * 16 + file]) {
                        if empty > 0 { row += String(empty); empty = 0 }
                        row.append(p.fenCharacter)
                    } else {
                        empty += 1
                    }
                }
                if empty > 0 { row += String(empty) }
                rows.append(row)
            }
            var c = ""
            if castling & Self.whiteKingside != 0 { c += "K" }
            if castling & Self.whiteQueenside != 0 { c += "Q" }
            if castling & Self.blackKingside != 0 { c += "k" }
            if castling & Self.blackQueenside != 0 { c += "q" }
            let epName = ep >= 0 ? Square(sq88: ep).name : "-"
            return "\(rows.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") \(c.isEmpty ? "-" : c) \(epName) \(halfmoveClock) \(fullmoveNumber)"
        }

        func computeHash() -> UInt64 {
            var h: UInt64 = 0
            for sq in 0..<128 where sq & 0x88 == 0 && board[sq] != 0 {
                h ^= Tables.pieceKey(board[sq], sq)
            }
            h ^= Tables.zobrist[Tables.zCastleBase + Int(castling)]
            if ep >= 0 { h ^= Tables.zobrist[Tables.zEPBase + (ep & 7)] }
            if sideToMove == .black { h ^= Tables.zobrist[Tables.zSide] }
            return h
        }

        /// True if a pawn of the side to move stands next to the double-pushed pawn.
        private func epCapturePossible(_ target: Int) -> Bool {
            let pawn: Int8 = sideToMove == .white ? 1 : -1
            let behind = sideToMove == .white ? target - 16 : target + 16
            for d in [-1, 1] {
                let s = behind + d
                if s & 0x88 == 0 && board[s] == pawn { return true }
            }
            return false
        }

        // MARK: Queries

        public func piece(at square: Square) -> Piece? { Piece(code: board[square.sq88]) }

        public func kingSquare(_ side: Side) -> Square {
            Square(sq88: side == .white ? whiteKing : blackKing)
        }

        public var isInCheck: Bool {
            isAttacked(sideToMove == .white ? whiteKing : blackKing, by: sideToMove.opponent)
        }

        public var enPassantSquare: Square? { ep >= 0 ? Square(sq88: ep) : nil }

        public func canCastle(_ side: Side, kingside: Bool) -> Bool {
            let bit = side == .white ? (kingside ? Self.whiteKingside : Self.whiteQueenside)
                                     : (kingside ? Self.blackKingside : Self.blackQueenside)
            return castling & bit != 0
        }

        /// All squares with their pieces.
        public var pieces: [(square: Square, piece: Piece)] {
            Square.all.compactMap { sq in piece(at: sq).map { (sq, $0) } }
        }

        /// Is `sq` (0x88) attacked by any piece of `side`?
        func isAttacked(_ sq: Int, by side: Side) -> Bool {
            let sign: Int8 = side == .white ? 1 : -1
            // Pawns
            if side == .white {
                let a = sq - 15, b = sq - 17
                if a & 0x88 == 0 && board[a] == 1 { return true }
                if b & 0x88 == 0 && board[b] == 1 { return true }
            } else {
                let a = sq + 15, b = sq + 17
                if a & 0x88 == 0 && board[a] == -1 { return true }
                if b & 0x88 == 0 && board[b] == -1 { return true }
            }
            let knight = 2 * sign, bishop = 3 * sign, rook = 4 * sign, queen = 5 * sign, king = 6 * sign
            for d in Tables.knight {
                let t = sq + d
                if t & 0x88 == 0 && board[t] == knight { return true }
            }
            for d in Tables.king {
                let t = sq + d
                if t & 0x88 == 0 && board[t] == king { return true }
            }
            for d in Tables.diagonal {
                var t = sq + d
                while t & 0x88 == 0 {
                    let p = board[t]
                    if p != 0 {
                        if p == bishop || p == queen { return true }
                        break
                    }
                    t += d
                }
            }
            for d in Tables.orthogonal {
                var t = sq + d
                while t & 0x88 == 0 {
                    let p = board[t]
                    if p != 0 {
                        if p == rook || p == queen { return true }
                        break
                    }
                    t += d
                }
            }
            return false
        }

        public func isSquareAttacked(_ square: Square, by side: Side) -> Bool {
            isAttacked(square.sq88, by: side)
        }

        /// No sequence of legal moves can lead to checkmate (FIDE dead-position basics):
        /// K vs K, K+minor vs K, and positions where all remaining minors are bishops on one colour.
        public var hasInsufficientMaterial: Bool {
            var minors = 0
            var knights = 0
            var bishopColors = 0 // bit 0 = dark, bit 1 = light
            for sq in 0..<128 where sq & 0x88 == 0 {
                let p = board[sq]
                if p == 0 { continue }
                switch abs(Int(p)) {
                case 1, 4, 5: return false
                case 2: knights += 1; minors += 1
                case 3:
                    minors += 1
                    bishopColors |= Square(sq88: sq).isLight ? 2 : 1
                default: break
                }
            }
            if minors <= 1 { return true }
            return knights == 0 && bishopColors != 3
        }

        // MARK: Move generation

        /// Appends pseudo-legal moves (may leave the king in check) to `moves`.
        /// With `capturesOnly`, only captures and queen promotions are generated.
        func generatePseudoLegal(into moves: inout [Move], capturesOnly: Bool = false) {
            let white = sideToMove == .white
            for i in 0..<64 {
                let s = i + (i & ~7)
                let p = board[s]
                if p == 0 || (p > 0) != white { continue }
                switch white ? Int(p) : Int(-p) {
                case 1: generatePawn(s, white: white, into: &moves, capturesOnly: capturesOnly)
                case 2: generateSteps(s, Tables.knight, white: white, into: &moves, capturesOnly: capturesOnly)
                case 3: generateSlides(s, Tables.diagonal, white: white, into: &moves, capturesOnly: capturesOnly)
                case 4: generateSlides(s, Tables.orthogonal, white: white, into: &moves, capturesOnly: capturesOnly)
                case 5:
                    generateSlides(s, Tables.diagonal, white: white, into: &moves, capturesOnly: capturesOnly)
                    generateSlides(s, Tables.orthogonal, white: white, into: &moves, capturesOnly: capturesOnly)
                default:
                    generateSteps(s, Tables.king, white: white, into: &moves, capturesOnly: capturesOnly)
                    if !capturesOnly { generateCastles(s, white: white, into: &moves) }
                }
            }
        }

        @inline(__always) private func isEnemy(_ p: Int8, white: Bool) -> Bool {
            white ? p < 0 : p > 0
        }

        private func generatePawn(_ s: Int, white: Bool, into moves: inout [Move], capturesOnly: Bool) {
            let dir = white ? 16 : -16
            let startRank = white ? 1 : 6
            let promoRank = white ? 7 : 0
            let one = s + dir
            if board[one] == 0 {
                if one >> 4 == promoRank {
                    addPromotions(from: s, to: one, flags: 0, into: &moves, queenOnly: capturesOnly)
                } else if !capturesOnly {
                    moves.append(Move(from: s, to: one))
                    let two = one + dir
                    if s >> 4 == startRank && board[two] == 0 {
                        moves.append(Move(from: s, to: two, flags: Move.doublePushFlag))
                    }
                }
            }
            for d in stride(from: dir - 1, through: dir + 1, by: 2) {
                let t = s + d
                if t & 0x88 != 0 { continue }
                if isEnemy(board[t], white: white) {
                    if t >> 4 == promoRank {
                        addPromotions(from: s, to: t, flags: Move.captureFlag, into: &moves, queenOnly: false)
                    } else {
                        moves.append(Move(from: s, to: t, flags: Move.captureFlag))
                    }
                } else if t == ep {
                    moves.append(Move(from: s, to: t, flags: Move.captureFlag | Move.enPassantFlag))
                }
            }
        }

        private func addPromotions(from: Int, to: Int, flags: UInt32, into moves: inout [Move], queenOnly: Bool) {
            moves.append(Move(from: from, to: to, promotion: PieceKind.queen.rawValue, flags: flags))
            guard !queenOnly else { return }
            moves.append(Move(from: from, to: to, promotion: PieceKind.knight.rawValue, flags: flags))
            moves.append(Move(from: from, to: to, promotion: PieceKind.rook.rawValue, flags: flags))
            moves.append(Move(from: from, to: to, promotion: PieceKind.bishop.rawValue, flags: flags))
        }

        private func generateSteps(_ s: Int, _ dirs: [Int], white: Bool, into moves: inout [Move], capturesOnly: Bool) {
            for d in dirs {
                let t = s + d
                if t & 0x88 != 0 { continue }
                let q = board[t]
                if q == 0 {
                    if !capturesOnly { moves.append(Move(from: s, to: t)) }
                } else if isEnemy(q, white: white) {
                    moves.append(Move(from: s, to: t, flags: Move.captureFlag))
                }
            }
        }

        private func generateSlides(_ s: Int, _ dirs: [Int], white: Bool, into moves: inout [Move], capturesOnly: Bool) {
            for d in dirs {
                var t = s + d
                while t & 0x88 == 0 {
                    let q = board[t]
                    if q == 0 {
                        if !capturesOnly { moves.append(Move(from: s, to: t)) }
                    } else {
                        if isEnemy(q, white: white) { moves.append(Move(from: s, to: t, flags: Move.captureFlag)) }
                        break
                    }
                    t += d
                }
            }
        }

        private func generateCastles(_ s: Int, white: Bool, into moves: inout [Move]) {
            let enemy: Side = white ? .black : .white
            let base = white ? 0 : 112
            guard s == base + 4 else { return }
            let ks = white ? Self.whiteKingside : Self.blackKingside
            let qs = white ? Self.whiteQueenside : Self.blackQueenside
            if castling & ks != 0, board[base + 5] == 0, board[base + 6] == 0,
               !isAttacked(base + 4, by: enemy), !isAttacked(base + 5, by: enemy), !isAttacked(base + 6, by: enemy) {
                moves.append(Move(from: base + 4, to: base + 6, flags: Move.castleFlag))
            }
            if castling & qs != 0, board[base + 3] == 0, board[base + 2] == 0, board[base + 1] == 0,
               !isAttacked(base + 4, by: enemy), !isAttacked(base + 3, by: enemy), !isAttacked(base + 2, by: enemy) {
                moves.append(Move(from: base + 4, to: base + 2, flags: Move.castleFlag))
            }
        }

        /// All legal moves in the position.
        public func legalMoves() -> [Move] {
            var pseudo: [Move] = []
            pseudo.reserveCapacity(64)
            generatePseudoLegal(into: &pseudo)
            var copy = self
            var legal: [Move] = []
            legal.reserveCapacity(pseudo.count)
            for m in pseudo {
                let u = copy.make(m)
                if !copy.leftKingInCheck { legal.append(m) }
                copy.unmake(m, u)
            }
            return legal
        }

        /// Legal moves starting from `square`.
        public func legalMoves(from square: Square) -> [Move] {
            legalMoves().filter { $0.from88 == square.sq88 }
        }

        public var hasLegalMove: Bool {
            var pseudo: [Move] = []
            generatePseudoLegal(into: &pseudo)
            var copy = self
            for m in pseudo {
                let u = copy.make(m)
                let ok = !copy.leftKingInCheck
                copy.unmake(m, u)
                if ok { return true }
            }
            return false
        }

        /// After `make`, whether the side that just moved left its own king attacked.
        @inline(__always) var leftKingInCheck: Bool {
            sideToMove == .white ? isAttacked(blackKing, by: .white) : isAttacked(whiteKing, by: .black)
        }

        /// Returns the legal move matching from/to/promotion, if any.
        public func legalMove(from: Square, to: Square, promotion: PieceKind? = nil) -> Move? {
            legalMoves().first { $0.from == from && $0.to == to && $0.promotion == promotion }
        }

        /// Parses UCI notation ("e2e4", "e7e8q") into a legal move.
        public func move(uci: String) -> Move? {
            let chars = Array(uci)
            guard chars.count == 4 || chars.count == 5,
                  let from = Square(String(chars[0...1])), let to = Square(String(chars[2...3])) else { return nil }
            var promo: PieceKind?
            if chars.count == 5 {
                guard let k = PieceKind(letter: chars[4]), PieceKind.promotions.contains(k) else { return nil }
                promo = k
            }
            return legalMove(from: from, to: to, promotion: promo)
        }

        // MARK: Make / unmake

        @discardableResult
        mutating func make(_ m: Move) -> Undo {
            let from = m.from88, to = m.to88, flags = m.flags
            let piece = board[from]
            let white = piece > 0
            var captured = board[to]
            var h = hash
            let undo: Undo
            if flags & Move.enPassantFlag != 0 {
                captured = white ? -1 : 1
                undo = Undo(captured: captured, castling: castling, ep: ep, halfmove: halfmoveClock, hash: hash)
                let victim = white ? to - 16 : to + 16
                board[victim] = 0
                h ^= Tables.pieceKey(captured, victim)
            } else {
                undo = Undo(captured: captured, castling: castling, ep: ep, halfmove: halfmoveClock, hash: hash)
                if captured != 0 { h ^= Tables.pieceKey(captured, to) }
            }
            if ep >= 0 { h ^= Tables.zobrist[Tables.zEPBase + (ep & 7)] }

            h ^= Tables.pieceKey(piece, from)
            board[from] = 0
            let placed: Int8 = m.promo != 0 ? (white ? Int8(m.promo) : -Int8(m.promo)) : piece
            board[to] = placed
            h ^= Tables.pieceKey(placed, to)

            if piece == 6 { whiteKing = to } else if piece == -6 { blackKing = to }

            if flags & Move.castleFlag != 0 {
                let rank = to & 0x70
                let (rf, rt) = (to & 7) == 6 ? (rank | 7, rank | 5) : (rank | 0, rank | 3)
                let rook = board[rf]
                board[rf] = 0
                board[rt] = rook
                h ^= Tables.pieceKey(rook, rf) ^ Tables.pieceKey(rook, rt)
            }

            h ^= Tables.zobrist[Tables.zCastleBase + Int(castling)]
            castling &= Tables.castleMask[from] & Tables.castleMask[to]
            h ^= Tables.zobrist[Tables.zCastleBase + Int(castling)]

            ep = -1
            if flags & Move.doublePushFlag != 0 {
                let enemyPawn: Int8 = white ? -1 : 1
                let l = to - 1, r = to + 1
                if (l & 0x88 == 0 && board[l] == enemyPawn) || (r & 0x88 == 0 && board[r] == enemyPawn) {
                    ep = (from + to) >> 1
                    h ^= Tables.zobrist[Tables.zEPBase + (ep & 7)]
                }
            }

            if piece == 1 || piece == -1 || captured != 0 { halfmoveClock = 0 } else { halfmoveClock += 1 }
            if !white { fullmoveNumber += 1 }
            sideToMove = white ? .black : .white
            h ^= Tables.zobrist[Tables.zSide]
            hash = h
            return undo
        }

        mutating func unmake(_ m: Move, _ u: Undo) {
            let from = m.from88, to = m.to88, flags = m.flags
            sideToMove = sideToMove.opponent
            let white = sideToMove == .white
            if !white { fullmoveNumber -= 1 }
            var piece = board[to]
            if m.promo != 0 { piece = white ? 1 : -1 }
            board[from] = piece
            if flags & Move.enPassantFlag != 0 {
                board[to] = 0
                board[white ? to - 16 : to + 16] = u.captured
            } else {
                board[to] = u.captured
            }
            if piece == 6 { whiteKing = from } else if piece == -6 { blackKing = from }
            if flags & Move.castleFlag != 0 {
                let rank = to & 0x70
                let (rf, rt) = (to & 7) == 6 ? (rank | 7, rank | 5) : (rank | 0, rank | 3)
                board[rf] = board[rt]
                board[rt] = 0
            }
            castling = u.castling
            ep = u.ep
            halfmoveClock = u.halfmove
            hash = u.hash
        }

        mutating func makeNull() -> Undo {
            let u = Undo(captured: 0, castling: castling, ep: ep, halfmove: halfmoveClock, hash: hash)
            var h = hash
            if ep >= 0 { h ^= Tables.zobrist[Tables.zEPBase + (ep & 7)] }
            ep = -1
            h ^= Tables.zobrist[Tables.zSide]
            sideToMove = sideToMove.opponent
            halfmoveClock += 1
            hash = h
            return u
        }

        mutating func unmakeNull(_ u: Undo) {
            sideToMove = sideToMove.opponent
            ep = u.ep
            halfmoveClock = u.halfmove
            hash = u.hash
        }

        /// The position after a (legal) move.
        public func applying(_ move: Move) -> Position {
            var p = self
            p.make(move)
            return p
        }

        // MARK: Perft

        /// Counts leaf nodes of the legal move tree to `depth` (move-generator verification).
        public func perft(_ depth: Int) -> Int {
            var p = self
            var buffers = [[Move]](repeating: [], count: depth + 1)
            return p.perftRecursive(depth, &buffers)
        }

        private mutating func perftRecursive(_ depth: Int, _ buffers: inout [[Move]]) -> Int {
            if depth == 0 { return 1 }
            var moves = buffers[depth]
            moves.removeAll(keepingCapacity: true)
            generatePseudoLegal(into: &moves)
            var count = 0
            for m in moves {
                let u = make(m)
                if !leftKingInCheck {
                    count += depth == 1 ? 1 : perftRecursive(depth - 1, &buffers)
                }
                unmake(m, u)
            }
            buffers[depth] = moves
            return count
        }
    }
}
