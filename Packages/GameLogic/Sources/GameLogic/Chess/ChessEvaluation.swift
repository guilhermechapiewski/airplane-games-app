extension Chess {
    /// Static evaluation: tapered material + piece-square tables, bishop pair, pawn structure,
    /// passed pawns, and a "mop-up" term that drives a lone king to the edge.
    enum Evaluation {
        // Material values (middlegame, endgame) indexed by kind (1...6).
        static let mgValue = [0, 100, 320, 335, 490, 960, 0]
        static let egValue = [0, 125, 300, 320, 530, 940, 0]
        static let phaseWeight = [0, 0, 1, 1, 2, 4, 0]
        static let maxPhase = 24

        // Piece-square tables from White's point of view, written with rank 8 on top
        // (so index 0 = a8). Values in centipawns.
        private static let pawn = [
            0, 0, 0, 0, 0, 0, 0, 0,
            50, 50, 50, 50, 50, 50, 50, 50,
            10, 10, 20, 30, 30, 20, 10, 10,
            5, 5, 10, 25, 25, 10, 5, 5,
            0, 0, 0, 20, 20, 0, 0, 0,
            5, -5, -10, 0, 0, -10, -5, 5,
            5, 10, 10, -20, -20, 10, 10, 5,
            0, 0, 0, 0, 0, 0, 0, 0,
        ]
        private static let pawnEnd = [
            0, 0, 0, 0, 0, 0, 0, 0,
            80, 80, 80, 80, 80, 80, 80, 80,
            50, 50, 50, 50, 50, 50, 50, 50,
            30, 30, 30, 30, 30, 30, 30, 30,
            15, 15, 15, 15, 15, 15, 15, 15,
            5, 5, 5, 5, 5, 5, 5, 5,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
        ]
        private static let knight = [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20, 0, 0, 0, 0, -20, -40,
            -30, 0, 10, 15, 15, 10, 0, -30,
            -30, 5, 15, 20, 20, 15, 5, -30,
            -30, 0, 15, 20, 20, 15, 0, -30,
            -30, 5, 10, 15, 15, 10, 5, -30,
            -40, -20, 0, 5, 5, 0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50,
        ]
        private static let bishop = [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 10, 10, 5, 0, -10,
            -10, 5, 5, 10, 10, 5, 5, -10,
            -10, 0, 10, 10, 10, 10, 0, -10,
            -10, 10, 10, 10, 10, 10, 10, -10,
            -10, 5, 0, 0, 0, 0, 5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20,
        ]
        private static let rook = [
            0, 0, 0, 0, 0, 0, 0, 0,
            5, 10, 10, 10, 10, 10, 10, 5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            0, 0, 0, 5, 5, 0, 0, 0,
        ]
        private static let queen = [
            -20, -10, -10, -5, -5, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -5, 0, 5, 5, 5, 5, 0, -5,
            0, 0, 5, 5, 5, 5, 0, -5,
            -10, 5, 5, 5, 5, 5, 0, -10,
            -10, 0, 5, 0, 0, 0, 0, -10,
            -20, -10, -10, -5, -5, -10, -10, -20,
        ]
        private static let kingMid = [
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
            20, 20, 0, 0, 0, 0, 20, 20,
            20, 30, 10, 0, 0, 10, 30, 20,
        ]
        private static let kingEnd = [
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10, 0, 0, -10, -20, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -30, 0, 0, 0, 0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50,
        ]

        /// Combined material + PST, indexed by `(code + 6) * 128 + sq88`, signed (White positive).
        static let tables: (mg: [Int], eg: [Int]) = {
            var mg = [Int](repeating: 0, count: 13 * 128)
            var eg = [Int](repeating: 0, count: 13 * 128)
            let mgPST = [[], pawn, knight, bishop, rook, queen, kingMid]
            let egPST = [[], pawnEnd, knight, bishop, rook, queen, kingEnd]
            for kind in 1...6 {
                for sq64 in 0..<64 {
                    let sq88 = sq64 + (sq64 & ~7)
                    let whiteIndex = sq64 ^ 56 // flip ranks for top-down tables
                    let blackIndex = sq64
                    mg[(6 + kind) * 128 + sq88] = mgValue[kind] + mgPST[kind][whiteIndex]
                    eg[(6 + kind) * 128 + sq88] = egValue[kind] + egPST[kind][whiteIndex]
                    mg[(6 - kind) * 128 + sq88] = -(mgValue[kind] + mgPST[kind][blackIndex])
                    eg[(6 - kind) * 128 + sq88] = -(egValue[kind] + egPST[kind][blackIndex])
                }
            }
            return (mg, eg)
        }()

        /// Bonus for a passed pawn by relative rank (0 = own back rank).
        static let passedBonus = [0, 10, 15, 25, 45, 75, 120, 0]
        /// Centralization measure for mop-up (0 at the centre, 6 in a corner).
        static func centerDistance(_ sq88: Int) -> Int {
            let f = sq88 & 7, r = sq88 >> 4
            return max(3 - f, f - 4) + max(3 - r, r - 4)
        }
    }
}

extension Chess.Position {
    /// Static evaluation in centipawns from the side to move's point of view.
    func evaluate() -> Int {
        typealias E = Chess.Evaluation
        var mg = 0, eg = 0, phase = 0
        var whiteBishops = 0, blackBishops = 0
        var whiteMaterial = 0, blackMaterial = 0
        // Per-file pawn info. Ranks are 0...7; sentinel -1 / 8 = none.
        var whiteMin = SIMD8<Int8>(repeating: 8), whiteMax = SIMD8<Int8>(repeating: -1)
        var blackMin = SIMD8<Int8>(repeating: 8), blackMax = SIMD8<Int8>(repeating: -1)
        var whiteCount = SIMD8<Int8>(repeating: 0), blackCount = SIMD8<Int8>(repeating: 0)

        let mgTable = E.tables.mg, egTable = E.tables.eg
        for i in 0..<64 {
            let s = i + (i & ~7)
            let p = board[s]
            if p == 0 { continue }
            let idx = (Int(p) + 6) * 128 + s
            mg += mgTable[idx]
            eg += egTable[idx]
            let kind = p > 0 ? Int(p) : Int(-p)
            phase += E.phaseWeight[kind]
            let f = i & 7, r = Int8(i >> 3)
            if p > 0 {
                whiteMaterial += E.egValue[kind]
                if kind == 3 { whiteBishops += 1 }
                if kind == 1 {
                    whiteCount[f] += 1
                    whiteMin[f] = min(whiteMin[f], r)
                    whiteMax[f] = max(whiteMax[f], r)
                }
            } else {
                blackMaterial += E.egValue[kind]
                if kind == 3 { blackBishops += 1 }
                if kind == 1 {
                    blackCount[f] += 1
                    blackMin[f] = min(blackMin[f], r)
                    blackMax[f] = max(blackMax[f], r)
                }
            }
        }
        if whiteBishops >= 2 { mg += 30; eg += 45 }
        if blackBishops >= 2 { mg -= 30; eg -= 45 }

        // Pawn structure.
        for f in 0..<8 {
            let wc = Int(whiteCount[f]), bc = Int(blackCount[f])
            if wc == 0 && bc == 0 { continue }
            let leftW = f > 0 ? whiteCount[f - 1] : 0, rightW = f < 7 ? whiteCount[f + 1] : 0
            let leftB = f > 0 ? blackCount[f - 1] : 0, rightB = f < 7 ? blackCount[f + 1] : 0
            if wc > 1 { mg -= 12 * (wc - 1); eg -= 20 * (wc - 1) }
            if bc > 1 { mg += 12 * (bc - 1); eg += 20 * (bc - 1) }
            if wc > 0 && leftW == 0 && rightW == 0 { mg -= 10 * wc; eg -= 15 * wc }
            if bc > 0 && leftB == 0 && rightB == 0 { mg += 10 * bc; eg += 15 * bc }
            // Passed pawns: the most advanced pawn on the file with no enemy pawns ahead on
            // this or adjacent files.
            if wc > 0 {
                let r = whiteMax[f]
                var blocked = blackMax[f] > r
                if f > 0 && blackMax[f - 1] > r { blocked = true }
                if f < 7 && blackMax[f + 1] > r { blocked = true }
                if !blocked {
                    let bonus = E.passedBonus[Int(r)]
                    mg += bonus / 2; eg += bonus
                }
            }
            if bc > 0 {
                let r = blackMin[f]
                var blocked = whiteMin[f] < r
                if f > 0 && whiteMin[f - 1] < r { blocked = true }
                if f < 7 && whiteMin[f + 1] < r { blocked = true }
                if !blocked {
                    let bonus = E.passedBonus[7 - Int(r)]
                    mg -= bonus / 2; eg -= bonus
                }
            }
        }

        // Mop-up: with a clear material edge in an endgame, push the losing king to the edge
        // and bring the winning king closer.
        let diff = whiteMaterial - blackMaterial
        if phase <= 8 && abs(diff) >= 400 {
            let winnerKing = diff > 0 ? whiteKing : blackKing
            let loserKing = diff > 0 ? blackKing : whiteKing
            let distance = abs((winnerKing & 7) - (loserKing & 7)) + abs((winnerKing >> 4) - (loserKing >> 4))
            let bonus = 10 * E.centerDistance(loserKing) + 4 * (14 - distance)
            eg += diff > 0 ? bonus : -bonus
        }

        let p = min(phase, E.maxPhase)
        var score = (mg * p + eg * (E.maxPhase - p)) / E.maxPhase
        // Lone minor pieces cannot win: scale down.
        if whiteMaterial - E.egValue[6] <= 330 && score > 0 && whiteCount == SIMD8(repeating: 0) { score /= 8 }
        if blackMaterial - E.egValue[6] <= 330 && score < 0 && blackCount == SIMD8(repeating: 0) { score /= 8 }
        let tempo = 10
        return (sideToMove == .white ? score : -score) + tempo
    }

    /// Whether the side to move has a piece other than pawns and king (null-move safety).
    var sideHasNonPawnMaterial: Bool {
        let white = sideToMove == .white
        for i in 0..<64 {
            let p = board[i + (i & ~7)]
            if white ? (p >= 2 && p <= 5) : (p <= -2 && p >= -5) { return true }
        }
        return false
    }
}
