import Foundation
import Testing
@testable import GameLogic

@Suite("Chess hints")
struct ChessHintTests {
    typealias C = Chess

    func game(_ fen: String) -> C.Game {
        do { return try C.Game(fen: fen) } catch { fatalError("bad test FEN \(fen): \(error)") }
    }

    @Test func suggestsALegalMoveQuickly() throws {
        for fen in [C.Position.startFEN, ChessRulesTests.kiwipete,
                    "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 4 4"] {
            let g = game(fen)
            let start = ContinuousClock.now
            let hint = try #require(C.Engine.hint(for: g))
            #expect(ContinuousClock.now - start < .milliseconds(1500), "\(fen)")
            #expect(g.position.legalMoves().contains(hint.move), "\(fen)")
            #expect(hint.piece.side == g.sideToMove)
        }
    }

    @Test func takesMateInOne() throws {
        for fen in ["6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1"] {
            let g = game(fen)
            let hint = try #require(C.Engine.hint(for: g))
            let after = g.position.applying(hint.move)
            #expect(after.isInCheck && !after.hasLegalMove, "\(fen)")
            #expect(hint.reason == .checkmate)
            #expect(hint.explanation == "Checkmate!")
        }
    }

    @Test func foolsMateForBlack() throws {
        var g = C.Game()
        for uci in ["f2f3", "e7e5", "g2g4"] { g.play(uci: uci) }
        let hint = try #require(C.Engine.hint(for: g))
        #expect(hint.move.uci == "d8h4")
        #expect(hint.spokenMove == "queen from d8 to h4")
    }

    @Test func findsAForcedMate() throws {
        let hint = try #require(C.Engine.hint(for: game("7k/8/8/8/8/8/1R6/R5K1 w - - 0 1")))
        #expect(hint.reason == .forcesMate(in: 2))
        #expect(hint.explanation == "Forces checkmate in 2 moves.")
    }

    @Test func takesAFreeQueen() throws {
        let hint = try #require(C.Engine.hint(for: game("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")))
        #expect(hint.move.uci == "d2d5")
        #expect(hint.reason == .captures(.queen, givesCheck: false))
        #expect(hint.explanation == "Captures a queen.")
    }

    @Test func savesAnAttackedQueen() throws {
        // The queen on e5 is attacked by the defended d6 pawn.
        let g = game("k7/2p5/3p4/4Q3/8/8/5PPP/6K1 w - - 0 1")
        let hint = try #require(C.Engine.hint(for: g))
        let next = g.position.applying(hint.move)
        let queen = try #require(next.pieces.first { $0.piece == C.Piece(.white, .queen) })
        #expect(!next.isSquareAttacked(queen.square, by: .black))
        // A quiet retreat is explained as escaping the threat.
        let retreat = C.Engine.makeHint(try #require(g.position.move(uci: "e5e4")), in: g.position, mateIn: nil)
        #expect(retreat.reason == .escapes(.queen))
        #expect(retreat.explanation == "Gets your queen out of danger.")
    }

    @Test func attackingAPieceIsExplained() throws {
        // After 1.e4 d5 2.Nf3 Qd6 3.Nc3 Qb4, a3 kicks the queen with a defended pawn.
        var g = C.Game()
        for uci in ["e2e4", "d7d5", "g1f3", "d8d6", "b1c3", "d6b4"] { g.play(uci: uci) }
        let kick = C.Engine.makeHint(try #require(g.position.move(uci: "a2a3")), in: g.position, mateIn: nil)
        #expect(kick.reason == .attacks(.queen))
        #expect(kick.explanation == "Attacks the queen.")
        // A pawn push into an undefended attacker's reach isn't a threat worth naming.
        let p = game("4k3/8/8/2q5/8/8/1P6/4K3 w - - 0 1").position
        let push = C.Engine.makeHint(try #require(p.move(uci: "b2b4")), in: p, mateIn: nil)
        #expect(push.reason == nil)
    }

    @Test func threatsAccountForDefenders() {
        // Attacked and undefended.
        let open = game("4k3/8/3n4/8/4N3/8/8/4K3 w - - 0 1").position
        #expect(C.Engine.isThreatened(C.Square("e4")!, in: open))
        // Defended by the f3 pawn and attacked only by an equal piece.
        let defended = game("4k3/8/3n4/8/4N3/5P2/8/4K3 w - - 0 1").position
        #expect(defended.isSquareAttacked(C.Square("e4")!, by: .white))
        #expect(!C.Engine.isThreatened(C.Square("e4")!, in: defended))
        // A defended rook attacked by a pawn is still in danger.
        let rook = game("k7/8/3p4/4R3/8/8/4K3/8 w - - 0 1").position
        #expect(C.Engine.isThreatened(C.Square("e5")!, in: rook))
    }

    @Test func openingMovesAreExplained() throws {
        let p = C.Position.start
        let knight = C.Engine.makeHint(try #require(p.move(uci: "g1f3")), in: p, mateIn: nil)
        #expect(knight.reason == .develops(.knight))
        #expect(knight.spokenMove == "knight from g1 to f3")
        #expect(C.Engine.makeHint(try #require(p.move(uci: "e2e4")), in: p, mateIn: nil).reason == .takesCenter)
        #expect(C.Engine.makeHint(try #require(p.move(uci: "a2a3")), in: p, mateIn: nil).reason == nil)

        let castle = game("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4").position
        let hint = C.Engine.makeHint(try #require(castle.move(uci: "e1g1")), in: castle, mateIn: nil)
        #expect(hint.reason == .castles)
        #expect(hint.spokenMove == "castle kingside")
    }

    @Test func noHintWhenTheGameIsOverOrStopped() {
        var mated = C.Game()
        for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] { mated.play(uci: uci) }
        #expect(C.Engine.hint(for: mated) == nil)
        #expect(C.Engine.hint(for: C.Game(), shouldStop: { true }) == nil)
    }
}
