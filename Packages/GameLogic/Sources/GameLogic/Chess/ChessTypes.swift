/// Chess: full rules (castling, en passant, promotion, draws), FEN/SAN notation,
/// and an alpha-beta computer opponent.
///
/// Internally the board is a 0x88 mailbox (128 squares, off-board test `sq & 0x88`).
/// The public API uses `Square` (0...63, a1 = 0, h8 = 63).
public enum Chess {}

extension Chess {
    public enum Side: Int, Codable, Sendable, CaseIterable {
        case white = 0, black = 1

        public var opponent: Side { self == .white ? .black : .white }
        public var name: String { self == .white ? "White" : "Black" }
    }

    public enum PieceKind: Int, Codable, Sendable, CaseIterable {
        case pawn = 1, knight, bishop, rook, queen, king

        /// Uppercase letter used by SAN and FEN.
        public var letter: Character {
            switch self {
            case .pawn: "P"
            case .knight: "N"
            case .bishop: "B"
            case .rook: "R"
            case .queen: "Q"
            case .king: "K"
            }
        }

        public var name: String {
            switch self {
            case .pawn: "pawn"
            case .knight: "knight"
            case .bishop: "bishop"
            case .rook: "rook"
            case .queen: "queen"
            case .king: "king"
            }
        }

        /// Conventional material value in pawns (king = 0).
        public var points: Int {
            switch self {
            case .pawn: 1
            case .knight, .bishop: 3
            case .rook: 5
            case .queen: 9
            case .king: 0
            }
        }

        public static let promotions: [PieceKind] = [.queen, .rook, .bishop, .knight]

        init?(letter: Character) {
            guard let k = PieceKind.allCases.first(where: { $0.letter == Character(letter.uppercased()) }) else { return nil }
            self = k
        }
    }

    public struct Piece: Hashable, Codable, Sendable {
        public let side: Side
        public let kind: PieceKind

        public init(_ side: Side, _ kind: PieceKind) {
            self.side = side
            self.kind = kind
        }

        /// Board code: +kind for white, -kind for black, 0 = empty.
        init?(code: Int8) {
            guard code != 0, let kind = PieceKind(rawValue: Int(code < 0 ? -code : code)) else { return nil }
            self.init(code > 0 ? .white : .black, kind)
        }

        var code: Int8 { side == .white ? Int8(kind.rawValue) : -Int8(kind.rawValue) }

        var fenCharacter: Character {
            side == .white ? kind.letter : Character(kind.letter.lowercased())
        }

        /// "white knight"
        public var name: String { "\(side.name.lowercased()) \(kind.name)" }
    }

    /// A board square, 0...63 with a1 = 0, b1 = 1, ..., h8 = 63.
    public struct Square: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
        public let index: Int

        public init(_ index: Int) {
            precondition((0..<64).contains(index), "square index out of range")
            self.index = index
        }

        public init(file: Int, rank: Int) {
            self.init(rank * 8 + file)
        }

        /// Parses algebraic names such as "e4".
        public init?(_ name: String) {
            let chars = Array(name)
            guard chars.count == 2,
                  let f = chars[0].asciiValue, let r = chars[1].asciiValue,
                  (97...104).contains(f), (49...56).contains(r) else { return nil }
            self.init(file: Int(f - 97), rank: Int(r - 49))
        }

        init(sq88: Int) { self.init((sq88 + (sq88 & 7)) >> 1) }

        public var file: Int { index & 7 }
        public var rank: Int { index >> 3 }
        var sq88: Int { index + (index & ~7) }
        public var isLight: Bool { (file + rank) % 2 == 1 }
        public var fileLetter: String { String(UnicodeScalar(UInt8(97 + file))) }
        public var name: String { fileLetter + String(rank + 1) }
        public var description: String { name }

        public static let all: [Square] = (0..<64).map { Square($0) }

        public static func < (a: Square, b: Square) -> Bool { a.index < b.index }
    }

    /// A move, packed into 32 bits: from(0x88) | to(0x88) << 8 | promotion << 16 | flags << 24.
    public struct Move: Hashable, Sendable, CustomStringConvertible {
        let raw: UInt32

        static let captureFlag: UInt32 = 1
        static let enPassantFlag: UInt32 = 2
        static let castleFlag: UInt32 = 4
        static let doublePushFlag: UInt32 = 8

        static let none = Move(raw: 0)

        init(raw: UInt32) { self.raw = raw }

        init(from: Int, to: Int, promotion: Int = 0, flags: UInt32 = 0) {
            raw = UInt32(from) | UInt32(to) << 8 | UInt32(promotion) << 16 | flags << 24
        }

        @inline(__always) var from88: Int { Int(raw & 0xFF) }
        @inline(__always) var to88: Int { Int((raw >> 8) & 0xFF) }
        @inline(__always) var promo: Int { Int((raw >> 16) & 0xFF) }
        @inline(__always) var flags: UInt32 { raw >> 24 }

        public var from: Square { Square(sq88: from88) }
        public var to: Square { Square(sq88: to88) }
        public var promotion: PieceKind? { promo == 0 ? nil : PieceKind(rawValue: promo) }
        public var isCapture: Bool { flags & Self.captureFlag != 0 }
        public var isEnPassant: Bool { flags & Self.enPassantFlag != 0 }
        public var isCastle: Bool { flags & Self.castleFlag != 0 }
        var isQuiet: Bool { flags & Self.captureFlag == 0 && promo == 0 }

        /// Long algebraic / UCI notation: "e2e4", "e7e8q".
        public var uci: String {
            from.name + to.name + (promotion.map { $0.letter.lowercased() } ?? "")
        }

        public var description: String { uci }

        /// For castling, the rook's (from, to) squares.
        public var castlingRook: (from: Square, to: Square)? {
            guard isCastle else { return nil }
            let to = to88
            let rank = to & 0x70
            return (to & 7) == 6
                ? (Square(sq88: rank | 7), Square(sq88: rank | 5))
                : (Square(sq88: rank | 0), Square(sq88: rank | 3))
        }

        /// For en passant, the square of the captured pawn.
        public var enPassantVictim: Square? {
            guard isEnPassant else { return nil }
            return Square(sq88: (from88 & 0x70) | (to88 & 7))
        }
    }

    public enum FENError: Error, Equatable {
        case invalid(String)
    }
}
