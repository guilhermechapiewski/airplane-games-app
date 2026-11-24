import Foundation
import Testing
@testable import GameLogic

@Suite("FreeCell")
struct FreeCellTests {
    typealias F = FreeCell
    typealias Card = FreeCell.Card

    func c(_ rank: Int, _ suit: F.Suit) -> Card { Card(rank, suit) }

    /// A state with the given columns (padded to eight) and cells.
    func state(_ columns: [[Card]], cells: [Card?] = [nil, nil, nil, nil], foundations: [Int] = [0, 0, 0, 0]) -> F.State {
        var cols = columns
        while cols.count < 8 { cols.append([]) }
        return F.State(deal: 1, tableau: cols, cells: cells, foundations: foundations)
    }

    /// Every card appears exactly once (foundations included).
    func expectComplete(_ s: F.State, sourceLocation: SourceLocation = #_sourceLocation) {
        let all = s.tableau.flatMap { $0 } + s.cells.compactMap { $0 } + (0..<4).flatMap { s.foundationCards($0) }
        #expect(all.count == 52, sourceLocation: sourceLocation)
        #expect(Set(all).count == 52, sourceLocation: sourceLocation)
    }

    /// Plays `moves` on `start`, checking each one is legal.
    func replay(_ moves: [F.Move], from start: F.State, sourceLocation: SourceLocation = #_sourceLocation) -> F.State {
        var s = start
        for move in moves {
            #expect(s.apply(move) != nil, "illegal \(move)", sourceLocation: sourceLocation)
        }
        return s
    }

    /// A position with no legal move at all: four Kings fill the cells, every column ends in a
    /// black Queen…9 (nothing stacks on another) and the Aces are buried.
    func deadPosition() -> F.State {
        let kings = F.Suit.allCases.map { c(13, $0) }
        let tops = [c(12, .spades), c(12, .clubs), c(11, .spades), c(11, .clubs),
                    c(10, .spades), c(10, .clubs), c(9, .spades), c(9, .clubs)]
        let aces = F.Suit.allCases.map { c(1, $0) }
        let rest = Card.deck.filter { !kings.contains($0) && !tops.contains($0) && !aces.contains($0) }
        var cols = Array(repeating: [Card](), count: 8)
        for (i, ace) in aces.enumerated() { cols[i].append(ace) }
        for (i, card) in rest.enumerated() { cols[i % 8].append(card) }
        for i in 0..<8 { cols[i].append(tops[i]) }
        return F.State(deal: 1, tableau: cols, cells: kings)
    }

    // MARK: Deals

    @Test func dealLaysOutAllCards() {
        let s = F.State.deal(number: 12345)
        expectComplete(s)
        #expect(s.tableau.map(\.count) == [7, 7, 7, 7, 6, 6, 6, 6])
        #expect(s.cells == [nil, nil, nil, nil])
        #expect(s.foundations == [0, 0, 0, 0])
        #expect(s.deal == 12345)
        #expect(s.moveCount == 0)
    }

    @Test func dealsAreDeterministicAndDistinct() {
        #expect(F.State.deal(number: 7) == F.State.deal(number: 7))
        #expect(F.State.deal(number: 7).tableau != F.State.deal(number: 8).tableau)
        let layouts = Set((1...200).map { F.State.deal(number: $0).tableau.flatMap { $0.map(\.id) } })
        #expect(layouts.count == 200)    }

    @Test func dealNumbersWrap() {
        #expect(F.normalizedDeal(1) == 1)
        #expect(F.normalizedDeal(F.maxDeal) == F.maxDeal)
        #expect(F.normalizedDeal(F.maxDeal + 1) == 1)
        #expect(F.normalizedDeal(0) == F.maxDeal)
        #expect(F.normalizedDeal(-5) == F.maxDeal - 5)
    }

    // MARK: Rules

    @Test func tableauBuildsDownInAlternatingColors() {
        let s = state([[c(8, .spades)], [c(7, .hearts)], [c(7, .clubs)], [c(6, .hearts)]])
        #expect(s.isLegal(.init(from: .tableau(1), to: .tableau(0))))       // red 7 on black 8
        #expect(!s.isLegal(.init(from: .tableau(2), to: .tableau(0))))      // black on black
        #expect(!s.isLegal(.init(from: .tableau(3), to: .tableau(0))))      // wrong rank
        #expect(s.isLegal(.init(from: .tableau(3), to: .tableau(2))))
        #expect(s.isLegal(.init(from: .tableau(0), to: .tableau(5))))       // any card to an empty column
        #expect(!s.isLegal(.init(from: .tableau(0), to: .tableau(0))))
        #expect(!s.isLegal(.init(from: .tableau(5), to: .tableau(0))))      // nothing to move
    }

    @Test func freeCellsHoldOneCard() {
        var s = state([[c(8, .spades), c(3, .hearts)]], cells: [c(5, .clubs), nil, nil, nil])
        #expect(!s.isLegal(.init(from: .tableau(0), to: .cell(0))))
        #expect(s.isLegal(.init(from: .tableau(0), to: .cell(1))))
        #expect(!s.isLegal(.init(from: .tableau(0), to: .cell(1), count: 2)))
        #expect(s.apply(.init(from: .tableau(0), to: .cell(1))) != nil)
        #expect(s.cells[1] == c(3, .hearts))
        #expect(s.freeCellCount == 2)
        #expect(s.isLegal(.init(from: .cell(1), to: .tableau(3))))
        #expect(!s.isLegal(.init(from: .cell(2), to: .tableau(3))))          // empty cell
    }

    @Test func foundationsBuildUpBySuit() {
        let s = state([[c(1, .hearts)], [c(2, .hearts)], [c(2, .spades)]], foundations: [0, 0, 0, 0])
        #expect(s.isLegal(.init(from: .tableau(0), to: .foundation(F.Suit.hearts.rawValue))))
        #expect(!s.isLegal(.init(from: .tableau(0), to: .foundation(F.Suit.spades.rawValue))))
        #expect(!s.isLegal(.init(from: .tableau(1), to: .foundation(F.Suit.hearts.rawValue))))
        let t = state([[c(2, .hearts)]], foundations: [0, 1, 0, 0])
        #expect(t.isLegal(.init(from: .tableau(0), to: .foundation(1))))
        #expect(t.foundationTarget(for: c(2, .hearts)) == 1)
        #expect(t.foundationCards(1) == [c(1, .hearts)])
        // Cards never come back off a foundation.
        #expect(!t.isLegal(.init(from: .foundation(1), to: .tableau(3))))
    }

    @Test func multiCardMoveLimit() {
        // (free cells + 1) × 2^(empty columns)
        let run = [c(9, .spades), c(8, .hearts), c(7, .clubs), c(6, .diamonds), c(5, .spades)]
        var cols: [[Card]] = [run, [c(10, .hearts)]]
        for i in 2..<8 { cols.append([c(13, F.Suit(rawValue: i % 4)!)]) }   // fill every other column
        let full = F.State(deal: 1, tableau: cols, cells: [c(2, .clubs), c(3, .clubs), c(4, .clubs), nil])
        #expect(full.maxMovable(toEmptyColumn: false) == 2)
        #expect(!full.isLegal(.init(from: .tableau(0), to: .tableau(1), count: 5)))
        #expect(full.isLegal(.init(from: .tableau(0), to: .tableau(1), count: 1)) == false) // 5♠ on 10♥: wrong rank

        let roomy = state([run, [c(10, .hearts)]])   // 4 free cells, 6 empty columns
        #expect(roomy.maxMovable(toEmptyColumn: false) == 5 * 64)
        #expect(roomy.maxMovable(toEmptyColumn: true) == 5 * 32)
        #expect(roomy.isLegal(.init(from: .tableau(0), to: .tableau(1), count: 5)))

        // 1 free cell, 1 empty column: 4 onto cards, 2 into the empty column.
        var tight = cols
        tight[7] = []
        let s = F.State(deal: 1, tableau: tight, cells: [c(2, .clubs), c(3, .clubs), c(4, .clubs), nil])
        #expect(s.maxMovable(toEmptyColumn: false) == 4)
        #expect(s.maxMovable(toEmptyColumn: true) == 2)
        let onto = [c(10, .hearts)]
        var withTarget = tight
        withTarget[1] = onto
        let s2 = F.State(deal: 1, tableau: withTarget, cells: s.cells)
        #expect(!s2.isLegal(.init(from: .tableau(0), to: .tableau(1), count: 5)))
        #expect(s2.isLegal(.init(from: .tableau(0), to: .tableau(7), count: 2)))
        #expect(!s2.isLegal(.init(from: .tableau(0), to: .tableau(7), count: 3)))
    }

    @Test func onlyOrderedRunsMoveTogether() {
        let s = state([[c(9, .spades), c(8, .hearts), c(7, .hearts)], [c(10, .hearts)]])
        #expect(s.runLength(0) == 1)
        #expect(!s.isLegal(.init(from: .tableau(0), to: .tableau(1), count: 3)))
        #expect(s.pickUpCount(pile: .tableau(0), index: 0) == nil)
        #expect(s.pickUpCount(pile: .tableau(0), index: 2) == 1)
        let ordered = state([[c(9, .spades), c(8, .hearts), c(7, .clubs)]])
        #expect(ordered.runLength(0) == 3)
        #expect(ordered.pickUpCount(pile: .tableau(0), index: 0) == 3)
    }

    @Test func applyMovesCardsAndCounts() {
        var s = state([[c(9, .spades), c(8, .hearts), c(7, .clubs)], [c(10, .hearts)]])
        let outcome = s.apply(.init(from: .tableau(0), to: .tableau(1), count: 3))
        #expect(outcome?.cards == [c(9, .spades), c(8, .hearts), c(7, .clubs)])
        #expect(s.tableau[0].isEmpty)
        #expect(s.tableau[1].count == 4)
        #expect(s.moveCount == 1)
        let before = s
        #expect(s.apply(.init(from: .tableau(0), to: .tableau(1))) == nil)
        #expect(s == before)
        s.apply(.init(from: .tableau(1), to: .cell(2)), counts: false)
        #expect(s.moveCount == 1)
        #expect(s.cells[2] == c(7, .clubs))
    }

    @Test func legalMovesAreAllLegal() {
        let s = F.State.deal(number: 99)
        let moves = s.legalMoves()
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy(s.isLegal))
        #expect(moves.contains { if case .cell = $0.to { true } else { false } })
        #expect(!s.isStuck)
    }

    @Test func deadPositionIsStuck() {
        let s = deadPosition()
        expectComplete(s)
        #expect(s.legalMoves().isEmpty)
        #expect(s.isStuck)
    }

    // MARK: Tap to move

    @Test func bestMovePrefersFoundationThenColumnThenCell() {
        let s = state([[c(5, .spades), c(1, .hearts)], [c(9, .spades), c(4, .hearts)], [c(8, .diamonds)], [c(5, .clubs)]])
        #expect(s.bestMove(forCardAt: .tableau(0), index: 1) == .init(from: .tableau(0), to: .foundation(1)))
        // 4♥ goes on 5♠? 5♠ is buried; 5♣ is a top: onto it.
        #expect(s.bestMove(forCardAt: .tableau(1), index: 1) == .init(from: .tableau(1), to: .tableau(3)))
        // 8♦ has no column to go on, so it goes to a free cell.
        #expect(s.bestMove(forCardAt: .tableau(2), index: 0) == .init(from: .tableau(2), to: .cell(0)))
        // Buried cards out of order can't be picked up.
        #expect(s.bestMove(forCardAt: .tableau(0), index: 0) == nil)
    }

    @Test func bestMoveForRunsAndCells() {
        let run = state([[c(2, .clubs), c(9, .spades), c(8, .hearts)], [c(13, .clubs)]], cells: [c(7, .clubs), nil, nil, nil])
        // A two-card run can't go to a cell: it goes to an empty column.
        #expect(run.bestMove(forCardAt: .tableau(0), index: 1) == .init(from: .tableau(0), to: .tableau(2), count: 2))
        // A cell card goes onto a matching column.
        #expect(run.bestMove(forCardAt: .cell(0), index: 0) == .init(from: .cell(0), to: .tableau(0)))
        // A whole column (headed by its bottom card) isn't shuffled into another empty column.
        let lone = state([[c(9, .spades), c(8, .hearts)]], cells: [c(1, .clubs), c(2, .clubs), c(3, .clubs), c(4, .clubs)])
        #expect(lone.bestMove(forCardAt: .tableau(0), index: 0) == nil)
    }

    @Test func movesForCardOffersOneFreeCell() {
        let s = state([[c(9, .spades), c(8, .hearts)]])
        let moves = s.moves(forCardAt: .tableau(0), index: 1)
        #expect(moves.filter { if case .cell = $0.to { true } else { false } }.count == 1)
        #expect(moves.contains(.init(from: .tableau(0), to: .tableau(1))))
    }

    // MARK: Automatic play

    @Test func safeFoundationMoves() {
        // Aces and Twos are always safe.
        #expect(state([[c(1, .spades)]]).nextSafeMove() == .init(from: .tableau(0), to: .foundation(0)))
        #expect(state([[c(2, .hearts)]], foundations: [0, 1, 0, 0]).nextSafeMove() == .init(from: .tableau(0), to: .foundation(1)))
        // A black 5 is safe only once both red 4s are home.
        let five = c(5, .spades)
        #expect(!state([[five]], foundations: [4, 3, 4, 0]).isSafeToFoundation(five))
        #expect(state([[five]], foundations: [4, 4, 4, 0]).isSafeToFoundation(five))
        // Free cells are checked first.
        let s = state([[c(1, .spades)]], cells: [nil, c(1, .hearts), nil, nil])
        #expect(s.nextSafeMove() == .init(from: .cell(1), to: .foundation(1)))
        #expect(state([[c(3, .spades)]]).nextSafeMove() == nil)
    }

    @Test func autoCompleteFinishesSortedColumns() {
        // Everything but the 9s…Kings is home; columns are in descending order.
        var cols: [[Card]] = []
        for suit in F.Suit.allCases { cols.append((9...13).reversed().map { c($0, suit) }) }
        var s = F.State(deal: 1, tableau: cols + [[], [], [], []], foundations: [8, 8, 8, 8])
        #expect(s.isTriviallySolvable)
        #expect(s.canAutoComplete)
        var steps = 0
        while let move = s.autoCompleteMove() {
            #expect(s.apply(move, counts: false) != nil)
            steps += 1
        }
        #expect(s.isWon)
        #expect(steps == 20)
        #expect(!s.canAutoComplete)
        #expect(!F.State.deal(number: 3).isTriviallySolvable)
    }

    @Test func sameLayoutIgnoresCellOrderAndMoveCount() {
        let a = state([[c(9, .spades)]], cells: [c(3, .hearts), nil, nil, nil])
        var b = state([[c(9, .spades)]], cells: [nil, nil, c(3, .hearts), nil])
        b.moveCount = 4
        #expect(a.sameLayout(as: b))
        #expect(!a.sameLayout(as: state([[c(9, .spades)]])))
    }

    // MARK: Solver & deals

    @Test func solverSolutionsReplayToAWin() {
        for n in [1, 2, 3, 500, 31_337] {
            let start = F.State.deal(number: n)
            let result = F.Solver.solve(start)
            guard result.solved else { continue }
            let end = replay(result.moves, from: start)
            #expect(end.isWon, "deal \(n)")
        }
    }

    @Test func solverSolvesNearlyEveryDeal() {
        let solved = (1...60).filter { F.Solver.solve(.deal(number: $0)).solved }.count
        #expect(solved >= 57)
    }

    @Test func solverIsFast() {
        let start = threadCPUTime()
        for n in 1...20 { _ = F.Solver.solve(.deal(number: n)) }
        #expect(threadCPUTime() - start < 10)
    }

    @Test func solverReportsDeadPositions() {
        let result = F.Solver.solve(deadPosition())
        #expect(result.status == .unsolvable)
        #expect(result.moves.isEmpty)
    }

    @Test func solverFinishesTrivialPositions() {
        var cols: [[Card]] = []
        for suit in F.Suit.allCases { cols.append((9...13).reversed().map { c($0, suit) }) }
        let s = F.State(deal: 1, tableau: cols + [[], [], [], []], foundations: [8, 8, 8, 8])
        let result = F.Solver.solve(s)
        #expect(result.solved && result.nodes == 0)
        #expect(replay(result.moves, from: s).isWon)
    }

    @Test func solvableDealIsDeterministicAndWinnable() throws {
        let a = try #require(F.solvableDeal(startingAt: 4242))
        let b = try #require(F.solvableDeal(startingAt: 4242))
        #expect(a.state == b.state)
        #expect(a.state.deal >= 4242 && a.state.deal < 4242 + 200)
        #expect(a.state == F.State.deal(number: a.state.deal))
        #expect(replay(a.solution, from: a.state).isWon)
        // Wraps past the last deal.
        let wrapped = try #require(F.solvableDeal(startingAt: F.maxDeal + 3))
        #expect(wrapped.state.deal >= 3)
        #expect(F.solvableDeal(startingAt: 1, shouldContinue: { false }) == nil)
    }

    // MARK: Hints

    @Test func hintStartsAWinningLine() throws {
        var s = F.State.deal(number: 2026)
        for _ in 0..<5 {
            guard case .move(let move) = F.hint(for: s) else {
                Issue.record("no hint for a solvable position")
                return
            }
            #expect(s.isLegal(move))
            s.apply(move)
            while let safe = s.nextSafeMove() { s.apply(safe, counts: false) }
            #expect(F.Solver.solve(s).solved)
        }
    }

    @Test func hintPlaysPendingSafeCardsFirst() {
        let s = state([[c(9, .spades), c(1, .hearts)], [c(13, .hearts)]], foundations: [13, 0, 13, 13])
        // Not a full deck, so only check the first suggestion.
        let hint = F.hint(for: s, nodeBudget: 1_000)
        if case .move(let move) = hint {
            #expect(move == .init(from: .tableau(0), to: .foundation(1)))
        }
    }

    @Test func hintForDeadAndWonPositions() {
        #expect(F.hint(for: deadPosition()) == .noSolution)
        let won = F.State(deal: 1, tableau: Array(repeating: [], count: 8), foundations: [13, 13, 13, 13])
        #expect(won.isWon)
        #expect(F.hint(for: won) == .noSolution)
    }

    @Test func hintGivesUpWithinBudget() {
        // A tiny budget can't prove anything about a fresh deal.
        #expect(F.hint(for: .deal(number: 77), nodeBudget: 1) == .unknown)
    }

    // MARK: Persistence

    @Test func stateRoundTripsThroughCodable() throws {
        var s = F.State.deal(number: 321)
        s.apply(.init(from: .tableau(0), to: .cell(0)))
        s.apply(.init(from: .tableau(1), to: .cell(3)))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(F.State.self, from: data)
        #expect(decoded == s)
        #expect(decoded.cells[1] == nil)
        let moves = [F.Move(from: .cell(1), to: .tableau(4), count: 1), F.Move(from: .tableau(2), to: .foundation(3), count: 1)]
        #expect(try JSONDecoder().decode([F.Move].self, from: JSONEncoder().encode(moves)) == moves)
    }
}
