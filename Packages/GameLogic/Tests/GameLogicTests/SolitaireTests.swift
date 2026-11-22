import Foundation
import Testing
@testable import GameLogic

@Suite("Solitaire")
struct SolitaireTests {
    typealias S = Solitaire
    typealias Card = Solitaire.Card

    // Shorthand: c(7, .hearts)
    func c(_ rank: Int, _ suit: S.Suit) -> Card { Card(rank, suit) }

    /// A state with the given columns (all face up unless `down` says otherwise) and everything
    /// else in the foundations / stock as specified. Card uniqueness is not required for rule tests.
    func state(_ columns: [[Card]], down: [Int] = [], stock: [Card] = [], waste: [Card] = [],
               foundations: [[Card]] = [[], [], [], []], mode: S.DrawMode = .draw1) -> S.State {
        var cols = columns.enumerated().map { S.Column(cards: $1, faceDownCount: $0 < down.count ? down[$0] : 0) }
        while cols.count < 7 { cols.append(S.Column()) }
        return S.State(drawMode: mode, stock: stock, waste: waste, foundations: foundations, tableau: cols)
    }

    /// All 52 cards appear exactly once across every pile.
    func expectComplete(_ s: S.State, sourceLocation: SourceLocation = #_sourceLocation) {
        let all = s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap(\.cards)
        #expect(all.count == 52, sourceLocation: sourceLocation)
        #expect(Set(all).count == 52, sourceLocation: sourceLocation)
        for column in s.tableau {
            #expect(column.faceDownCount >= 0 && (column.faceDownCount < column.cards.count || column.cards.isEmpty),
                    sourceLocation: sourceLocation)
            #expect(S.isRun(column.faceUpCards), sourceLocation: sourceLocation)
        }
        for pile in s.foundations {
            for (i, card) in pile.enumerated() {
                #expect(card.rank == i + 1 && card.suit == pile[0].suit, sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: Cards

    @Test func deckHas52UniqueCardsWithStableIDs() {
        #expect(Card.deck.count == 52)
        #expect(Set(Card.deck.map(\.id)) == Set(0..<52))
        for card in Card.deck { #expect(Card(id: card.id) == card) }
        #expect(Card(id: 52) == nil)
        #expect(Card(id: -1) == nil)
    }

    @Test func cardNamesAndColors() {
        #expect(c(7, .hearts).name == "7 of Hearts")
        #expect(c(1, .spades).name == "Ace of Spades")
        #expect(c(12, .diamonds).name == "Queen of Diamonds")
        #expect(c(13, .clubs).rankSymbol == "K")
        #expect(c(10, .clubs).description == "10♣")
        #expect(c(5, .diamonds).isRed && c(5, .hearts).isRed)
        #expect(!c(5, .clubs).isRed && !c(5, .spades).isRed)
    }

    @Test func stackingRequiresAlternatingColorAndDescendingRank() {
        #expect(c(6, .hearts).canStack(on: c(7, .spades)))
        #expect(c(6, .clubs).canStack(on: c(7, .diamonds)))
        #expect(!c(6, .diamonds).canStack(on: c(7, .hearts)))
        #expect(!c(6, .spades).canStack(on: c(7, .clubs)))
        #expect(!c(5, .hearts).canStack(on: c(7, .spades)))
        #expect(!c(8, .hearts).canStack(on: c(7, .spades)))
        #expect(S.isRun([c(9, .spades), c(8, .hearts), c(7, .clubs)]))
        #expect(!S.isRun([c(9, .spades), c(8, .hearts), c(7, .diamonds)]))
    }

    // MARK: Dealing

    @Test func dealHasStandardLayout() {
        let s = S.State.deal(drawMode: .draw1, seed: 42)
        for (i, column) in s.tableau.enumerated() {
            #expect(column.cards.count == i + 1)
            #expect(column.faceDownCount == i)
        }
        #expect(s.stock.count == 24)
        #expect(s.waste.isEmpty)
        #expect(s.foundations.allSatisfy { $0.isEmpty })
        #expect(s.score == 0 && s.moveCount == 0)
        expectComplete(s)
    }

    @Test func dealIsDeterministic() {
        #expect(S.State.deal(drawMode: .draw3, seed: 7) == S.State.deal(drawMode: .draw3, seed: 7))
        #expect(S.State.deal(drawMode: .draw3, seed: 7) != S.State.deal(drawMode: .draw3, seed: 8))
        #expect(S.shuffledDeck(seed: 1) != Card.deck)
        #expect(Set(S.shuffledDeck(seed: 1)) == Set(Card.deck))
    }

    // MARK: Stock & waste

    @Test func drawOneTakesTopCard() {
        var s = state([], stock: [c(1, .spades), c(2, .spades), c(3, .spades)])
        let outcome = s.apply(.draw)
        #expect(outcome?.cards == [c(3, .spades)])
        #expect(s.waste == [c(3, .spades)])
        #expect(s.stock == [c(1, .spades), c(2, .spades)])
        #expect(s.wasteFan == 1)
        #expect(s.moveCount == 1)
    }

    @Test func drawThreeTurnsOverAGroup() {
        let stock = (1...5).map { c($0, .hearts) }
        var s = state([], stock: stock, mode: .draw3)
        s.apply(.draw)
        // Top of the stock (5) goes face-down-first, so 3 ends up playable.
        #expect(s.waste == [c(5, .hearts), c(4, .hearts), c(3, .hearts)])
        #expect(s.waste.last == c(3, .hearts))
        #expect(s.wasteFan == 3)
        s.apply(.draw)
        #expect(s.waste.last == c(1, .hearts))
        #expect(s.wasteFan == 2)
        #expect(s.stock.isEmpty)
    }

    @Test func recycleRestoresStockOrderAndCostsPoints() {
        let stock = (1...4).map { c($0, .clubs) }
        var s = state([], stock: stock, mode: .draw1)
        s.score = 150
        #expect(!s.isLegal(.recycle))
        for _ in 0..<4 { s.apply(.draw) }
        #expect(!s.isLegal(.draw))
        let outcome = s.apply(.recycle)
        #expect(outcome?.scoreDelta == -100)
        #expect(s.stock == stock)
        #expect(s.waste.isEmpty)
        #expect(s.passes == 1)
        #expect(s.score == 50)
        // Score never goes negative.
        for _ in 0..<4 { s.apply(.draw) }
        s.apply(.recycle)
        #expect(s.score == 0)

        var three = state([], stock: stock, mode: .draw3)
        three.score = 30
        three.apply(.draw); three.apply(.draw)
        #expect(three.apply(.recycle)?.scoreDelta == -20)
    }

    @Test func drawOrRecycleAlternates() {
        var s = state([], stock: [c(1, .clubs)])
        #expect(s.drawOrRecycle()?.move == .draw)
        #expect(s.drawOrRecycle()?.move == .recycle)
        #expect(s.stock == [c(1, .clubs)])
        var empty = state([])
        #expect(empty.drawOrRecycle() == nil)
    }

    @Test func playingFromWasteShrinksTheFan() {
        let stock = [c(9, .spades), c(1, .hearts), c(1, .spades), c(1, .clubs)]
        var s = state([], stock: stock, mode: .draw3)
        s.apply(.draw)
        #expect(s.wasteFan == 3)
        #expect(s.apply(S.Move(from: .waste, to: .foundation(0))) != nil)
        #expect(s.wasteFan == 2)
        #expect(s.apply(S.Move(from: .waste, to: .foundation(1))) != nil)
        #expect(s.apply(S.Move(from: .waste, to: .foundation(2))) != nil)
        #expect(s.wasteFan == 0)
        s.apply(.draw)
        #expect(s.wasteFan == 1)
    }

    // MARK: Tableau rules

    @Test func tableauAcceptsOppositeColorOneLower() {
        var s = state([[c(8, .spades)], [c(7, .hearts)], [c(7, .clubs)]])
        #expect(s.isLegal(S.Move(from: .tableau(1), to: .tableau(0))))
        #expect(!s.isLegal(S.Move(from: .tableau(2), to: .tableau(0))))
        #expect(!s.isLegal(S.Move(from: .tableau(0), to: .tableau(0))))
        let outcome = s.apply(S.Move(from: .tableau(1), to: .tableau(0)))
        #expect(outcome?.scoreDelta == 0)
        #expect(s.tableau[0].cards == [c(8, .spades), c(7, .hearts)])
        #expect(s.tableau[1].isEmpty)
    }

    @Test func onlyKingsGoToEmptyColumns() {
        let s = state([[c(12, .hearts)], [c(13, .clubs)], []])
        #expect(!s.isLegal(S.Move(from: .tableau(0), to: .tableau(2))))
        #expect(s.isLegal(S.Move(from: .tableau(1), to: .tableau(2))))
    }

    @Test func runsMoveTogetherAndMustBeValid() {
        var s = state([[c(10, .diamonds), c(9, .spades), c(8, .hearts)], [c(10, .clubs)], [c(9, .hearts)]], down: [1])
        // 9♠ 8♥ can't go on the black 10♣, and the face-down 10♦ can't be lifted.
        #expect(!s.isLegal(S.Move(from: .tableau(0), to: .tableau(1), count: 2)))
        #expect(!s.isLegal(S.Move(from: .tableau(0), to: .tableau(1), count: 3)))
        var t = state([[c(4, .clubs), c(9, .spades), c(8, .hearts)], [c(10, .diamonds)]], down: [1])
        let outcome = t.apply(S.Move(from: .tableau(0), to: .tableau(1), count: 2))
        #expect(outcome != nil)
        #expect(t.tableau[1].cards == [c(10, .diamonds), c(9, .spades), c(8, .hearts)])
        // The exposed 4♣ flips face up for 5 points.
        #expect(outcome?.flipped == c(4, .clubs))
        #expect(outcome?.scoreDelta == 5)
        #expect(t.tableau[0].faceDownCount == 0)
        // An invalid sequence can't be lifted as a run.
        s.tableau[2] = S.Column(cards: [c(9, .hearts), c(8, .diamonds)], faceDownCount: 0)
        #expect(s.pickUpCount(pile: .tableau(2), index: 0) == nil)
        #expect(s.pickUpCount(pile: .tableau(2), index: 1) == 1)
    }

    @Test func kingLedRunToEmptyColumn() {
        var s = state([[c(2, .clubs), c(13, .hearts), c(12, .spades)], []], down: [1])
        let move = S.Move(from: .tableau(0), to: .tableau(1), count: 2)
        #expect(s.isLegal(move))
        s.apply(move)
        #expect(s.tableau[1].cards == [c(13, .hearts), c(12, .spades)])
        #expect(s.tableau[0].cards == [c(2, .clubs)] && s.tableau[0].faceDownCount == 0)
    }

    // MARK: Foundations

    @Test func foundationsBuildSameSuitUpFromAce() {
        var s = state([[c(1, .hearts)], [c(2, .hearts)], [c(2, .spades)], [c(3, .hearts), c(2, .clubs)]])
        #expect(!s.isLegal(S.Move(from: .tableau(1), to: .foundation(0))))
        #expect(s.apply(S.Move(from: .tableau(0), to: .foundation(0)))?.scoreDelta == 10)
        #expect(!s.isLegal(S.Move(from: .tableau(2), to: .foundation(0))))
        #expect(s.apply(S.Move(from: .tableau(1), to: .foundation(0))) != nil)
        // Only single cards go to a foundation.
        #expect(!s.isLegal(S.Move(from: .tableau(3), to: .foundation(0), count: 2)))
        #expect(s.foundations[0] == [c(1, .hearts), c(2, .hearts)])
        // Foundation-to-foundation is never allowed.
        #expect(!s.isLegal(S.Move(from: .foundation(0), to: .foundation(1))))
    }

    @Test func foundationTargetPicksFirstEmptyForAces() {
        let s = state([], foundations: [[c(1, .spades)], [], [], []])
        #expect(s.foundationTarget(for: c(1, .hearts)) == 1)
        #expect(s.foundationTarget(for: c(2, .spades)) == 0)
        #expect(s.foundationTarget(for: c(2, .clubs)) == nil)
    }

    @Test func scoringForEveryMoveKind() {
        var s = state([[c(8, .spades)], [c(13, .clubs)]], waste: [c(7, .hearts), c(1, .diamonds)],
                      foundations: [[c(1, .hearts), c(2, .hearts), c(3, .hearts)], [], [], []])
        #expect(s.apply(S.Move(from: .waste, to: .foundation(1)))?.scoreDelta == 10)
        #expect(s.apply(S.Move(from: .waste, to: .tableau(0)))?.scoreDelta == 5)
        s.tableau[1] = S.Column(cards: [c(4, .spades)])
        #expect(s.apply(S.Move(from: .foundation(0), to: .tableau(1)))?.scoreDelta == -15)
        #expect(s.score == 0) // 10 + 5 - 15
    }

    @Test func illegalMovesDoNotChangeState() {
        var s = S.State.deal(drawMode: .draw1, seed: 3)
        let before = s
        let bogus: [S.Move] = [
            S.Move(from: .tableau(9), to: .tableau(0)),
            S.Move(from: .tableau(0), to: .tableau(-1)),
            S.Move(from: .foundation(0), to: .tableau(0)),
            S.Move(from: .waste, to: .tableau(0)),
            S.Move(from: .tableau(6), to: .tableau(0), count: 7),
            S.Move(from: .tableau(6), to: .tableau(0), count: 0),
            S.Move(from: .stock, to: .tableau(0)),
            S.Move(from: .tableau(0), to: .waste),
            S.Move(from: .waste, to: .stock),
        ]
        for move in bogus { #expect(s.apply(move) == nil, "\(move)") }
        #expect(s == before)
    }

    // MARK: Win & auto-complete

    @Test func winDetectionAndAutoComplete() {
        // Everything on the foundations except a few face-up cards.
        var foundations: [[Card]] = S.Suit.allCases.map { suit in (1...13).map { c($0, suit) } }
        let kingS = foundations[0].removeLast(), queenS = foundations[0].removeLast()
        let kingH = foundations[1].removeLast()
        let kingD = foundations[2].removeLast()
        var s = state([[kingH, queenS], [kingS]], stock: [kingD], foundations: foundations)
        #expect(!s.isWon)
        #expect(s.canAutoComplete)
        var steps = 0
        while s.autoCompleteStep() != nil { steps += 1 }
        #expect(steps == 4)
        #expect(s.isWon)
        #expect(!s.canAutoComplete)
        #expect(s.score == 40)
        expectComplete(s)
    }

    @Test func autoCompleteRequiresAllCardsFaceUp() {
        let s = state([[c(5, .spades), c(4, .hearts)]], down: [1])
        #expect(!s.canAutoComplete)
    }

    // MARK: Best move & hints

    @Test func bestMovePrefersFoundationThenNonEmptyColumn() {
        let s = state([[c(1, .clubs)], [c(8, .spades)], [c(8, .clubs)], [], [c(7, .hearts)], [c(13, .hearts)]])
        #expect(s.bestMove(forCardAt: .tableau(0), index: 0)?.to == .foundation(0))
        #expect(s.bestMove(forCardAt: .tableau(4), index: 0)?.to == .tableau(1))
        // A King already at the bottom of its column isn't shuffled to another empty column.
        #expect(s.bestMove(forCardAt: .tableau(5), index: 0) == nil)
        // A face-down card can't be moved.
        let hidden = state([[c(3, .clubs), c(1, .hearts)]], down: [1])
        #expect(hidden.bestMove(forCardAt: .tableau(0), index: 0) == nil)
        #expect(hidden.bestMove(forCardAt: .tableau(0), index: 1)?.to == .foundation(0))
    }

    @Test func bestMoveMovesBuriedKingToEmptyColumn() {
        let s = state([[c(2, .clubs), c(13, .diamonds)], []], down: [1])
        #expect(s.bestMove(forCardAt: .tableau(0), index: 1) == S.Move(from: .tableau(0), to: .tableau(1)))
    }

    @Test func bestMoveFromFoundationGoesToTableau() {
        let s = state([[c(6, .hearts)]], foundations: [[c(1, .spades), c(2, .spades), c(3, .spades), c(4, .spades), c(5, .spades)], [], [], []])
        #expect(s.bestMove(forCardAt: .foundation(0), index: 4) == S.Move(from: .foundation(0), to: .tableau(0)))
        #expect(s.bestMove(forCardAt: .foundation(0), index: 3) == nil)
    }

    @Test func movesForCardListsAllTargets() {
        let s = state([[c(6, .hearts)], [c(7, .spades)], [c(7, .clubs)], []])
        let targets = s.moves(forCardAt: .tableau(0), index: 0).map(\.to)
        #expect(targets == [.tableau(1), .tableau(2)])
    }

    @Test func hintPrefersFoundation() {
        let s = state([[c(9, .spades)], [c(1, .diamonds)]], waste: [c(8, .hearts)])
        #expect(s.hint() == S.Move(from: .tableau(1), to: .foundation(0)))
    }

    @Test func hintRevealsHiddenCards() {
        let s = state([[c(4, .clubs), c(7, .hearts)], [c(8, .spades)]], down: [1])
        #expect(s.hint() == S.Move(from: .tableau(0), to: .tableau(1)))
    }

    @Test func hintSuggestsDrawingWhenAStockCardHelps() {
        let s = state([[c(8, .spades)]], stock: [c(7, .hearts), c(2, .clubs)])
        #expect(s.hint() == .draw)
        let recycle = state([[c(8, .spades)]], waste: [c(7, .hearts), c(2, .clubs)])
        #expect(recycle.hint() == .recycle)
    }

    @Test func hintClearsAColumnForAKing() {
        let s = state([[c(9, .spades)], [c(8, .hearts)]], stock: [c(13, .clubs)])
        #expect(s.hint() == S.Move(from: .tableau(1), to: .tableau(0)))
    }

    @Test func hintFreesACardForItsFoundation() {
        // 6♥ is playable to the hearts foundation once 5♠ moves onto 6♦.
        let hearts = (1...5).map { c($0, .hearts) }
        let s = state([[c(13, .clubs), c(6, .hearts), c(5, .spades)], [c(6, .diamonds)]], down: [1],
                      foundations: [hearts, [], [], []])
        #expect(s.hint() == S.Move(from: .tableau(0), to: .tableau(1)))
    }

    @Test func stuckWhenNothingUseful() {
        let s = state([[c(9, .spades)], [c(9, .clubs)]], stock: [c(5, .hearts), c(3, .diamonds)])
        #expect(s.hint() == nil)
        #expect(s.isStuck)
        let won = state([], foundations: S.Suit.allCases.map { suit in (1...13).map { c($0, suit) } })
        #expect(won.isWon && !won.isStuck)
    }

    @Test func reachableStockCardsInDrawThree() {
        // Stock top is last: draws yield 3 then (after recycle) the cycle repeats.
        let stock = (1...7).map { c($0, .spades) }
        let s = state([], stock: stock, mode: .draw3)
        // Draw 1: waste top = 5, draw 2: top = 2, draw 3: top = 1. After recycle same cycle.
        #expect(Set(s.reachableStockCards()) == Set([c(5, .spades), c(2, .spades), c(1, .spades)]))
        let one = state([], stock: stock, mode: .draw1)
        #expect(Set(one.reachableStockCards()) == Set(stock))
    }

    // MARK: Random play keeps invariants

    @Test func randomPlayKeepsInvariants() {
        var rng = SeededRandom(seed: 2024)
        for game in 0..<20 {
            var s = S.State.deal(drawMode: game.isMultiple(of: 2) ? .draw1 : .draw3, seed: rng.next())
            for _ in 0..<300 {
                let moves = s.legalMoves()
                guard let move = moves.randomElement(using: &rng) else { break }
                let before = s.moveCount
                #expect(s.apply(move) != nil)
                #expect(s.moveCount == before + 1)
                #expect(s.score >= 0)
            }
            expectComplete(s)
        }
    }

    @Test func legalMovesAreAllLegal() {
        let s = S.State.deal(drawMode: .draw1, seed: 11)
        let moves = s.legalMoves()
        #expect(moves.contains(.draw))
        #expect(moves.allSatisfy(s.isLegal))
        for t in 0..<7 {
            for i in s.tableau[t].cards.indices {
                if let best = s.bestMove(forCardAt: .tableau(t), index: i) { #expect(s.isLegal(best)) }
            }
        }
    }

    // MARK: Persistence

    @Test func codableRoundTripIsCompact() throws {
        var s = S.State.deal(drawMode: .draw3, seed: 8)
        s.apply(.draw)
        if let hint = s.hint() { s.apply(hint) }
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(S.State.self, from: data) == s)
        #expect(data.count < 1200)
        #expect(try JSONEncoder().encode(c(7, .hearts)) == Data("19".utf8))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Card.self, from: Data("99".utf8)) }
    }

    @Test func timeBonus() {
        #expect(S.Scoring.timeBonus(seconds: 10) == 0)
        #expect(S.Scoring.timeBonus(seconds: 100) == 7000)
        #expect(S.Scoring.timeBonus(seconds: 700) == 1000)
    }

    // MARK: Solver

    /// Replays a solver solution through the public rules and finishes with auto-complete.
    func replayWins(_ start: S.State, _ moves: [S.Move]) -> Bool {
        var s = start
        for move in moves { guard s.apply(move) != nil else { return false } }
        guard S.Solver.isSolved(s) else { return false }
        while s.autoCompleteStep() != nil {}
        return s.isWon
    }

    @Test func solverSolutionsReplayToAWin() {
        var solved = 0
        for seed in UInt64(1)...12 {
            let start = S.State.deal(drawMode: .draw1, seed: seed)
            let result = S.Solver.solve(start, nodeBudget: 8_000)
            if result.solved {
                solved += 1
                #expect(replayWins(start, result.moves), "seed \(seed)")
            }
        }
        #expect(solved >= 4)
    }

    @Test func solverHandlesNearlyFinishedGame() {
        var foundations: [[Card]] = S.Suit.allCases.map { suit in (1...13).map { c($0, suit) } }
        let k = foundations[3].removeLast(), q = foundations[3].removeLast()
        let s = state([[k], [q]], foundations: foundations)
        let result = S.Solver.solve(s, nodeBudget: 100)
        #expect(result.solved)
        #expect(replayWins(s, result.moves))
    }

    @Test func solverReportsUnprovenWithinBudget() {
        let start = S.State.deal(drawMode: .draw3, seed: 5)
        let result = S.Solver.solve(start, nodeBudget: 1)
        #expect(result.nodes <= 1)
        if !result.solved { #expect(result.moves.isEmpty) }
    }

    @Test func solverKeyIgnoresScoreAndFan() {
        var a = S.State.deal(drawMode: .draw3, seed: 9)
        var b = a
        b.score = 500
        b.moveCount = 42
        #expect(S.Solver.key(a) == S.Solver.key(b))
        a.apply(.draw)
        #expect(S.Solver.key(a) != S.Solver.key(b))
    }

    @Test func safeMovesOnlyPlayLowOrCoveredCards() {
        let foundations: [[Card]] = [[c(1, .spades)], [c(1, .hearts)], [], []]
        let s = state([[c(2, .spades)], [c(3, .spades)], [c(2, .hearts)]], foundations: foundations)
        #expect(S.Solver.isSafe(c(2, .spades), in: s))
        #expect(!S.Solver.isSafe(c(3, .spades), in: s))
        var t = s
        let played = S.Solver.playSafeMoves(&t)
        #expect(played.count == 2)
        #expect(t.foundationCount == 4)
    }

    @Test func winnableDealIsProvenAndReplayable() {
        for mode in S.DrawMode.allCases {
            let deal = S.winnableDeal(drawMode: mode, seed: 77, maxAttempts: 30, nodeBudget: 8_000)
            #expect(deal.state == S.State.deal(drawMode: mode, seed: deal.seed))
            if deal.provenWinnable {
                let result = S.Solver.solve(deal.state, nodeBudget: 8_000)
                #expect(result.solved)
                #expect(replayWins(deal.state, result.moves))
            }
            expectComplete(deal.state)
        }
        // Determinism.
        let a = S.winnableDeal(drawMode: .draw1, seed: 5, maxAttempts: 5, nodeBudget: 2_000)
        let b = S.winnableDeal(drawMode: .draw1, seed: 5, maxAttempts: 5, nodeBudget: 2_000)
        #expect(a.seed == b.seed && a.provenWinnable == b.provenWinnable)
    }

    @Test func winnableDealFallsBackGracefully() {
        let deal = S.winnableDeal(drawMode: .draw3, seed: 1, maxAttempts: 3, nodeBudget: 1) { false }
        #expect(deal.state.stock.count == 24)
        expectComplete(deal.state)
    }
}
