import Foundation
import Testing
@testable import GameLogic

@Suite("Chess rules")
struct ChessRulesTests {
    typealias C = Chess

    func pos(_ fen: String) -> C.Position {
        do { return try C.Position(fen: fen) } catch { fatalError("bad test FEN \(fen): \(error)") }
    }

    // MARK: Perft

    static let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

    @Test(arguments: [(1, 20), (2, 400), (3, 8902), (4, 197_281)])
    func perftStart(depth: Int, nodes: Int) {
        #expect(C.Position.start.perft(depth) == nodes)
    }

    @Test(arguments: [(1, 48), (2, 2039), (3, 97_862)])
    func perftKiwipete(depth: Int, nodes: Int) {
        #expect(pos(Self.kiwipete).perft(depth) == nodes)
    }

    /// Position 3: en passant and rook endgame pins.
    @Test(arguments: [(1, 14), (2, 191), (3, 2812), (4, 43_238)])
    func perftPosition3(depth: Int, nodes: Int) {
        #expect(pos("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1").perft(depth) == nodes)
    }

    /// Position 4: promotions, castling rights lost by captures.
    @Test(arguments: [(1, 6), (2, 264), (3, 9467)])
    func perftPosition4(depth: Int, nodes: Int) {
        #expect(pos("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1").perft(depth) == nodes)
        // Mirrored version must give identical counts.
        #expect(pos("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1").perft(depth) == nodes)
    }

    /// Position 5.
    @Test(arguments: [(1, 44), (2, 1486), (3, 62_379)])
    func perftPosition5(depth: Int, nodes: Int) {
        #expect(pos("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8").perft(depth) == nodes)
    }

    // MARK: FEN

    @Test func fenRoundTrip() {
        for fen in [C.Position.startFEN, Self.kiwipete,
                    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
                    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"] {
            #expect(pos(fen).fen == fen)
        }
    }

    @Test func invalidFENsAreRejected() {
        for fen in ["", "8/8/8/8/8/8/8/8 w - - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1",
                    "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",
                    "3Qk3/8/8/8/8/8/8/4K3 w - - 0 1"] {
            #expect(throws: C.FENError.self) { try C.Position(fen: fen) }
        }
    }

    @Test func enPassantSquareOnlyWhenCapturable() {
        var g = C.Game()
        g.play(san: "e4")
        #expect(g.position.enPassantSquare == nil)
        #expect(g.position.fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
        g.play(san: "a6"); g.play(san: "e5"); g.play(san: "d5")
        #expect(g.position.enPassantSquare == C.Square("d6"))
    }

    // MARK: Hashing

    @Test func incrementalHashMatchesFullRecompute() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<20 {
            var p = pos(Self.kiwipete)
            for _ in 0..<40 {
                let moves = p.legalMoves()
                guard !moves.isEmpty else { break }
                p = p.applying(moves[Int(rng.next() % UInt64(moves.count))])
                #expect(p.hash == p.computeHash())
                #expect(pos(p.fen).hash == p.hash)
            }
        }
    }

    @Test func makeUnmakeRestoresPosition() {
        let original = pos(Self.kiwipete)
        var p = original
        var moves: [C.Move] = []
        p.generatePseudoLegal(into: &moves)
        for m in moves {
            let u = p.make(m)
            p.unmake(m, u)
            #expect(p == original)
        }
    }

    // MARK: Special moves

    @Test func castlingConditions() {
        // Both sides can castle.
        let open = pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let sans = Set(open.legalMoves().map { open.san($0) })
        #expect(sans.contains("O-O") && sans.contains("O-O-O"))
        // Cannot castle out of check.
        let inCheck = pos("r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1")
        #expect(!inCheck.legalMoves().contains { $0.isCastle })
        // Cannot castle through an attacked square (f1) but queenside is fine.
        let through = pos("r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1")
        let t = through.legalMoves().filter(\.isCastle).map { through.san($0) }
        #expect(t == ["O-O-O"])
        // Queenside: b1 may be attacked, but must be empty.
        let b1Attacked = pos("r3k2r/8/8/8/8/8/1r6/R3K2R w KQkq - 0 1")
        #expect(b1Attacked.legalMoves().contains { $0.isCastle && $0.to.name == "c1" })
        let blocked = pos("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1")
        #expect(!blocked.legalMoves().contains { $0.isCastle && $0.to.name == "c1" })
        // Cannot castle into check.
        let into = pos("r3k2r/8/8/8/8/8/6r1/R3K2R w KQkq - 0 1")
        #expect(!into.legalMoves().contains { $0.isCastle && $0.to.name == "g1" })
    }

    @Test func castlingMovesRookAndClearsRights() {
        var g = C.Game(position: pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let played = g.play(san: "O-O"); #expect(played)
        #expect(g.position.piece(at: C.Square("g1")!) == C.Piece(.white, .king))
        #expect(g.position.piece(at: C.Square("f1")!) == C.Piece(.white, .rook))
        #expect(g.position.piece(at: C.Square("h1")!) == nil)
        #expect(!g.position.canCastle(.white, kingside: false))
        #expect(g.lastMove?.castlingRook?.from.name == "h1")
        // Capturing a rook removes the opponent's right.
        var h = C.Game(position: pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let capturedRook = h.play(san: "Rxa8+"); #expect(capturedRook)
        #expect(!h.position.canCastle(.black, kingside: false))
        #expect(h.position.canCastle(.black, kingside: true))
        #expect(h.position.fen.hasPrefix("R3k2r/8/8/8/8/8/8/4K2R b Kk"))
    }

    @Test func enPassantCapture() {
        var g = C.Game(position: pos("4k3/8/8/8/1p6/8/P7/4K3 w - - 0 1"))
        g.play(san: "a4")
        #expect(g.position.enPassantSquare?.name == "a3")
        let played = g.play(san: "bxa3"); #expect(played)
        #expect(g.position.piece(at: C.Square("a4")!) == nil)
        #expect(g.lastMove?.isEnPassant == true)
        #expect(g.lastMove?.enPassantVictim?.name == "a4")
        #expect(g.captured(by: .black) == [.pawn])
    }

    @Test func enPassantIllegalWhenItExposesKing() {
        // Capturing would expose the black king on the 4th rank to the rook.
        let p = pos("8/8/8/8/k2Pp2R/8/8/4K3 b - d3 0 1")
        #expect(!p.legalMoves().contains { $0.isEnPassant })
    }

    @Test func promotionOptions() {
        let p = pos("8/P3k3/8/8/8/8/8/4K3 w - - 0 1")
        let promos = p.legalMoves().filter { $0.promotion != nil }
        #expect(Set(promos.compactMap(\.promotion)) == [.queen, .rook, .bishop, .knight])
        var g = C.Game(position: p)
        let played = g.play(san: "a8=N"); #expect(played)
        #expect(g.position.piece(at: C.Square("a8")!) == C.Piece(.white, .knight))
        #expect(g.sanMoves == ["a8=N"])
    }

    // MARK: SAN

    @Test func sanDisambiguationAndSymbols() {
        let p = pos("4k3/8/8/8/8/8/K7/R6R w - - 0 1")
        let rd1 = p.legalMoves().first { $0.from.name == "a1" && $0.to.name == "d1" }!
        #expect(p.san(rd1) == "Rad1")
        let knights = pos("4k3/8/8/8/8/2N5/8/2N1K3 w - - 0 1")
        let ne2 = knights.legalMoves().first { $0.from.name == "c1" && $0.to.name == "e2" }!
        #expect(knights.san(ne2) == "N1e2")
        let queens = pos("1k6/8/8/8/Q6Q/8/8/Q3K3 w - - 0 1")
        let qd4 = queens.legalMoves().first { $0.from.name == "a4" && $0.to.name == "d4" }!
        #expect(queens.san(qd4) == "Qa4d4")
        var g = C.Game()
        for m in ["f3", "e5", "g4", "Qh4"] { let played = g.play(san: m); #expect(played) }
        #expect(g.sanMoves.last == "Qh4#")
        #expect(g.pgnMoveText == "1. f3 e5 2. g4 Qh4#")
    }

    @Test func sanParsingRoundTrip() {
        var rng = SeededRandom(seed: 42)
        var g = C.Game()
        for _ in 0..<80 {
            guard !g.isOver else { break }
            let moves = g.position.legalMoves()
            let m = moves[Int(rng.next() % UInt64(moves.count))]
            let san = g.position.san(m)
            #expect(g.position.move(san: san) == m)
            #expect(g.position.move(uci: m.uci) == m)
            g.play(m)
        }
    }

    // MARK: Results

    @Test func foolsMateIsCheckmate() {
        var g = C.Game()
        for m in ["f3", "e5", "g4", "Qh4#"] { g.play(san: m) }
        #expect(g.outcome == .checkmate(winner: .black))
        let played = g.play(san: "a3"); #expect(!played)
    }

    @Test func stalemate() {
        let g = C.Game(position: pos("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(g.outcome == .stalemate)
    }

    @Test func fiftyMoveRule() {
        var g = C.Game(position: pos("4k3/8/8/8/8/8/8/R3K3 w - - 99 80"))
        #expect(g.outcome == nil)
        g.play(san: "Ra2")
        #expect(g.outcome == .fiftyMoveRule)
        // Checkmate on the 100th half-move takes precedence.
        var h = C.Game(position: pos("6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 80"))
        h.play(san: "Ra8#")
        #expect(h.outcome == .checkmate(winner: .white))
    }

    @Test func threefoldRepetition() {
        var g = C.Game()
        for m in ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1"] {
            g.play(san: m)
            #expect(g.outcome == nil)
        }
        #expect(g.repetitionCount == 2)
        g.play(san: "Ng8")
        #expect(g.repetitionCount == 3)
        #expect(g.outcome == .threefoldRepetition)
    }

    @Test func insufficientMaterial() {
        let dead = ["8/8/4k3/8/8/3K4/8/8 w - - 0 1",
                    "8/8/4k3/8/8/3KN3/8/8 w - - 0 1",
                    "8/8/4k3/8/8/3KB3/8/8 w - - 0 1",
                    "8/2b5/4k3/8/8/3KB3/8/8 w - - 0 1"] // same-coloured bishops (c7 and e3 are dark)
        for fen in dead { #expect(pos(fen).hasInsufficientMaterial, "\(fen)") }
        let alive = ["8/8/4k3/8/8/3KP3/8/8 w - - 0 1",
                     "8/1b6/4k3/8/8/3KB3/8/8 w - - 0 1", // opposite-coloured bishops
                     "8/8/4k3/8/8/3KNN2/8/8 w - - 0 1",
                     "8/8/4kn2/8/8/3KB3/8/8 w - - 0 1"]
        for fen in alive { #expect(!pos(fen).hasInsufficientMaterial, "\(fen)") }
        var g = C.Game(position: pos("8/8/4k3/8/8/3K4/4r3/8 w - - 0 1"))
        g.play(san: "Kxe2")
        #expect(g.outcome == .insufficientMaterial)
    }

    @Test func resignation() {
        var g = C.Game()
        g.play(san: "e4")
        g.resign(.black)
        #expect(g.outcome == .resignation(winner: .white))
        #expect(g.outcome?.reason == "Black resigned")
        g.undo()
        #expect(g.outcome == nil)
        #expect(g.moves.count == 1)
    }

    // MARK: Game record

    @Test func gameCodableRoundTripAndUndo() throws {
        var g = C.Game()
        for m in ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"] { let played = g.play(san: m); #expect(played) }
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(C.Game.self, from: data)
        #expect(decoded == g)
        #expect(decoded.position == g.position)
        #expect(decoded.sanMoves == g.sanMoves)
        var u = decoded
        u.undo(); u.undo()
        #expect(u.position.fen == "rnbqkb1r/pp2pppp/3p1n2/8/3NP3/8/PPP2PPP/RNBQKB1R w KQkq - 1 5")
        #expect(g.captured(by: .white) == [.pawn])
        #expect(g.captured(by: .black) == [.pawn])
        #expect(g.materialBalance == 0)
    }

    @Test func illegalMovesAreRejected() {
        var g = C.Game()
        let played = g.play(uci: "e2e5"); #expect(!played)
        let played2 = g.play(uci: "e7e5"); #expect(!played2)
        let played3 = g.play(uci: "zz"); #expect(!played3)
        #expect(g.moves.isEmpty)
    }
}

@Suite("Chess engine")
struct ChessEngineTests {
    typealias C = Chess

    func pos(_ fen: String) -> C.Position {
        do { return try C.Position(fen: fen) } catch { fatalError("bad test FEN \(fen): \(error)") }
    }

    @Test func findsMateInOne() {
        let p = pos("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        let r = C.Engine.search(p, maxDepth: 4)
        #expect(r.move.map { p.san($0) } == "Ra8#")
        #expect(r.mateIn == 1)
        // Black to move too.
        let b = pos("r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")
        let rb = C.Engine.search(b, maxDepth: 4)
        #expect(rb.move.map { b.san($0) } == "Ra1#")
    }

    @Test func findsMateInTwo() throws {
        for fen in ["7k/8/8/8/8/8/1R6/R5K1 w - - 0 1",
                    "r5k1/1r6/8/8/8/8/8/7K b - - 0 1"] {
            let p = pos(fen)
            let r = C.Engine.search(p, maxDepth: 6)
            let move = try #require(r.move)
            #expect(r.mateIn == 2, "\(fen)")
            // Every reply must allow a mate in one.
            let next = p.applying(move)
            for reply in next.legalMoves() {
                let after = next.applying(reply)
                let mates = after.legalMoves().contains { m in
                    let q = after.applying(m)
                    return q.isInCheck && !q.hasLegalMove
                }
                #expect(mates, "\(fen): \(p.san(move)) \(next.san(reply)) has no mate")
            }
        }
    }

    @Test(arguments: [C.Level.intermediate, .advanced, .master])
    func doesNotHangTheQueen(level: C.Level) throws {
        // The queen on e5 is attacked by the defended d6 pawn.
        let g = C.Game(position: pos("k7/2p5/3p4/4Q3/8/8/5PPP/6K1 w - - 0 1"))
        let move = try #require(C.Engine.chooseMove(for: g, level: level, seed: 3))
        let next = g.position.applying(move)
        let queen = next.pieces.first { $0.piece == C.Piece(.white, .queen) }
        let q = try #require(queen)
        #expect(!next.isSquareAttacked(q.square, by: .black), "\(level): \(g.position.san(move))")
    }

    @Test func takesAFreeQueen() {
        let p = pos("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")
        let r = C.Engine.search(p, maxDepth: 3)
        #expect(r.move.map { p.san($0) } == "Rxd5")
    }

    @Test func everyLevelPlaysOnlyLegalMoves() {
        for level in C.Level.allCases {
            var g = C.Game()
            var seed: UInt64 = UInt64(level.rawValue) * 1000
            let plies = level.rawValue >= 4 ? 4 : 16
            for _ in 0..<plies {
                guard !g.isOver else { break }
                seed += 1
                guard let m = C.Engine.chooseMove(for: g, level: level, seed: seed) else {
                    Issue.record("no move at \(level)")
                    break
                }
                #expect(g.position.legalMoves().contains(m))
                let played = g.play(m); #expect(played)
            }
        }
    }

    @Test func searchRespectsTimeLimit() {
        let start = Date()
        let r = C.Engine.search(pos(ChessRulesTests.kiwipete), maxDepth: 30, timeLimit: 0.3)
        let elapsed = Date().timeIntervalSince(start)
        #expect(r.move != nil)
        #expect(r.depth >= 1)
        #expect(elapsed < 1.5)
    }

    @Test func cancellationStopsSearchQuickly() async {
        let start = Date()
        let task = Task.detached {
            C.Engine.search(C.Position.start, maxDepth: 30, timeLimit: 30)
        }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        _ = await task.value
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func noMoveWhenGameIsOver() {
        var g = C.Game()
        for m in ["f3", "e5", "g4", "Qh4#"] { g.play(san: m) }
        #expect(C.Engine.chooseMove(for: g, level: .master) == nil)
    }

    @Test func avoidsRepetitionWhenWinning() {
        // With a big material edge, the engine should not choose a move that repeats into a draw.
        var g = C.Game(position: pos("4k3/8/8/8/8/8/8/QQ2K3 b - - 0 1"))
        // Qaa1 now would repeat the start position a third time.
        for m in ["Kf8", "Qa7", "Ke8", "Qaa1", "Kf8", "Qa7", "Ke8"] { let ok = g.play(san: m); #expect(ok) }
        #expect(g.repetitionCount == 2)
        #expect(g.outcome == nil)
        if let m = C.Engine.chooseMove(for: g, level: .advanced, seed: 1) {
            var h = g
            h.play(m)
            #expect(h.outcome != .threefoldRepetition)
        }
    }
}
