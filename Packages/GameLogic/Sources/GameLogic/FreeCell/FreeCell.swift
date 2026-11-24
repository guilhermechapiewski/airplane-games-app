/// FreeCell: every card is dealt face up into eight columns. Four free cells hold one card
/// each; build the four foundations up by suit from Ace to King.
public enum FreeCell {
    public typealias Card = Solitaire.Card
    public typealias Suit = Solitaire.Suit

    /// Deal numbers run from 1 to `maxDeal`.
    public static let maxDeal = 999_999
    public static let columnCount = 8
    public static let cellCount = 4

    /// A place cards can live. Foundations are indexed by suit (`Suit.rawValue`).
    public enum Pile: Hashable, Codable, Sendable {
        case cell(Int)
        case foundation(Int)
        case tableau(Int)
    }

    /// A move of `count` cards from the top of one pile to another.
    public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
        public var from: Pile
        public var to: Pile
        public var count: Int

        public init(from: Pile, to: Pile, count: Int = 1) {
            self.from = from
            self.to = to
            self.count = count
        }

        public var description: String { "\(from)→\(to)×\(count)" }
    }

    /// What a move did, for animation and feedback.
    public struct Outcome: Equatable, Sendable {
        public var move: Move
        public var cards: [Card]
    }

    // MARK: - State

    public struct State: Codable, Equatable, Sendable {
        /// The deal number this game started from.
        public let deal: Int
        /// Eight columns, bottom → top.
        public internal(set) var tableau: [[Card]]
        /// Four free cells.
        public internal(set) var cells: [Card?]
        /// Cards on each suit's foundation (index = `Suit.rawValue`), 0...13.
        public internal(set) var foundations: [Int]
        /// Moves made by the player (automatic foundation plays aren't counted).
        public internal(set) var moveCount: Int

        public init(deal: Int, tableau: [[Card]], cells: [Card?] = [nil, nil, nil, nil],
                    foundations: [Int] = [0, 0, 0, 0], moveCount: Int = 0) {
            precondition(tableau.count == FreeCell.columnCount && cells.count == FreeCell.cellCount && foundations.count == 4)
            self.deal = deal
            self.tableau = tableau
            self.cells = cells
            self.foundations = foundations
            self.moveCount = moveCount
        }

        /// Deal number `number`: a seeded shuffle dealt left to right, row by row
        /// (the first four columns get seven cards, the others six).
        public static func deal(number: Int) -> State {
            let deck = Solitaire.shuffledDeck(seed: FreeCell.seed(forDeal: number))
            var columns = Array(repeating: [Card](), count: FreeCell.columnCount)
            for (i, card) in deck.enumerated() { columns[i % FreeCell.columnCount].append(card) }
            return State(deal: number, tableau: columns)
        }

        // MARK: Queries

        public var isWon: Bool { foundations.allSatisfy { $0 == 13 } }
        public var foundationCount: Int { foundations.reduce(0, +) }
        public var freeCellCount: Int { cells.filter { $0 == nil }.count }
        public var emptyColumnCount: Int { tableau.filter(\.isEmpty).count }

        /// The cards on a suit's foundation, Ace first.
        public func foundationCards(_ f: Int) -> [Card] {
            guard foundations.indices.contains(f), let suit = Suit(rawValue: f) else { return [] }
            return (0..<foundations[f]).map { Card($0 + 1, suit) }
        }

        public func cards(in pile: Pile) -> [Card] {
            switch pile {
            case .cell(let c): cells.indices.contains(c) ? cells[c].map { [$0] } ?? [] : []
            case .foundation(let f): foundationCards(f)
            case .tableau(let t): tableau.indices.contains(t) ? tableau[t] : []
            }
        }

        public func top(of pile: Pile) -> Card? { cards(in: pile).last }

        /// Where a card is: its pile and index within it (bottom = 0).
        public func location(of card: Card) -> (pile: Pile, index: Int)? {
            if let c = cells.firstIndex(of: card) { return (.cell(c), 0) }
            if foundations[card.suit.rawValue] >= card.rank { return (.foundation(card.suit.rawValue), card.rank - 1) }
            for (t, column) in tableau.enumerated() {
                if let i = column.firstIndex(of: card) { return (.tableau(t), i) }
            }
            return nil
        }

        /// How many cards can move together: (free cells + 1) × 2^(empty columns),
        /// not counting the target column when it is empty.
        public func maxMovable(toEmptyColumn: Bool) -> Int {
            let empties = max(0, emptyColumnCount - (toEmptyColumn ? 1 : 0))
            return (freeCellCount + 1) << empties
        }

        /// Length of the ordered run (down, alternating colors) on top of column `t`.
        public func runLength(_ t: Int) -> Int {
            let column = tableau[t]
            guard !column.isEmpty else { return 0 }
            var n = 1
            while n < column.count, column[column.count - n].canStack(on: column[column.count - n - 1]) { n += 1 }
            return n
        }

        public func canPlace(_ card: Card, onFoundation f: Int) -> Bool {
            card.suit.rawValue == f && foundations[f] == card.rank - 1
        }

        public func foundationTarget(for card: Card) -> Int? {
            canPlace(card, onFoundation: card.suit.rawValue) ? card.suit.rawValue : nil
        }

        /// The cards a move would pick up, if they form a run that may be picked up.
        func movingCards(from pile: Pile, count: Int) -> ArraySlice<Card>? {
            guard count >= 1 else { return nil }
            switch pile {
            case .cell(let c):
                guard count == 1, cells.indices.contains(c), let card = cells[c] else { return nil }
                return [card][...]
            case .foundation:
                return nil
            case .tableau(let t):
                guard tableau.indices.contains(t), count <= tableau[t].count else { return nil }
                let run = tableau[t].suffix(count)
                return Solitaire.isRun(run) ? run : nil
            }
        }

        public func isLegal(_ move: Move) -> Bool {
            guard move.from != move.to, let moving = movingCards(from: move.from, count: move.count),
                  let lead = moving.first else { return false }
            switch move.to {
            case .cell(let c):
                return move.count == 1 && cells.indices.contains(c) && cells[c] == nil
            case .foundation(let f):
                return move.count == 1 && (0..<4).contains(f) && canPlace(lead, onFoundation: f)
            case .tableau(let t):
                guard tableau.indices.contains(t) else { return false }
                if let top = tableau[t].last {
                    return lead.canStack(on: top) && move.count <= maxMovable(toEmptyColumn: false)
                }
                return move.count <= maxMovable(toEmptyColumn: true)
            }
        }

        static let allTargets: [Pile] = (0..<4).map(Pile.foundation) + (0..<8).map(Pile.tableau) + (0..<4).map(Pile.cell)

        /// Every legal move (cards only ever leave cells and columns).
        public func legalMoves() -> [Move] {
            var moves: [Move] = []
            var sources: [(Pile, Int)] = []
            for (c, card) in cells.enumerated() where card != nil { sources.append((.cell(c), 1)) }
            for t in tableau.indices where !tableau[t].isEmpty {
                for n in 1...runLength(t) { sources.append((.tableau(t), n)) }
            }
            for (pile, n) in sources {
                for target in Self.allTargets {
                    let move = Move(from: pile, to: target, count: n)
                    if isLegal(move) { moves.append(move) }
                }
            }
            return moves
        }

        /// How many cards are lifted when grabbing the card at `index` of `pile`, if it can be grabbed.
        public func pickUpCount(pile: Pile, index: Int) -> Int? {
            let count = cards(in: pile).count - index
            guard index >= 0, count >= 1, movingCards(from: pile, count: count) != nil else { return nil }
            return count
        }

        /// Legal moves that pick up the card at `index` of `pile` (and the cards on top of it).
        public func moves(forCardAt pile: Pile, index: Int) -> [Move] {
            guard let count = pickUpCount(pile: pile, index: index) else { return [] }
            var moves = Self.allTargets.map { Move(from: pile, to: $0, count: count) }.filter(isLegal)
            // One free cell is enough to offer.
            if let firstCell = moves.firstIndex(where: { if case .cell = $0.to { true } else { false } }) {
                moves = moves.enumerated().filter { i, m in
                    if case .cell = m.to { return i == firstCell }
                    return true
                }.map(\.1)
            }
            return moves
        }

        /// The smartest destination for a tapped card: its foundation, then a column with cards,
        /// then a free cell (single cards), then an empty column.
        public func bestMove(forCardAt pile: Pile, index: Int) -> Move? {
            guard let count = pickUpCount(pile: pile, index: index) else { return nil }
            let lead = cards(in: pile)[index]
            if count == 1, let f = foundationTarget(for: lead) { return Move(from: pile, to: .foundation(f)) }
            var empty: Move?
            for t in tableau.indices {
                let move = Move(from: pile, to: .tableau(t), count: count)
                guard isLegal(move) else { continue }
                if !tableau[t].isEmpty { return move }
                if empty == nil { empty = move }
            }
            let wholeColumn: Bool = if case .tableau = pile { index == 0 } else { false }
            if count == 1, case .tableau = pile, let c = cells.firstIndex(where: { $0 == nil }) {
                // A lone card is better off in a cell than shuffled to another empty column.
                return Move(from: pile, to: .cell(c))
            }
            return wholeColumn ? nil : empty
        }

        /// No move at all is possible.
        public var isStuck: Bool { !isWon && legalMoves().isEmpty }

        // MARK: Automatic play

        /// A card that is no longer needed on the tableau: Aces and Twos, or a card whose
        /// opposite-color cards one rank lower are already on their foundations.
        public func isSafeToFoundation(_ card: Card) -> Bool {
            guard foundationTarget(for: card) != nil else { return false }
            if card.rank <= 2 { return true }
            let opposite = Suit.allCases.filter { $0.isRed != card.isRed }
            return opposite.allSatisfy { foundations[$0.rawValue] >= card.rank - 1 }
        }

        /// The next safe foundation play (free cells first, then columns left to right).
        public func nextSafeMove() -> Move? {
            for (c, card) in cells.enumerated() {
                if let card, isSafeToFoundation(card) { return Move(from: .cell(c), to: .foundation(card.suit.rawValue)) }
            }
            for (t, column) in tableau.enumerated() {
                if let card = column.last, isSafeToFoundation(card) {
                    return Move(from: .tableau(t), to: .foundation(card.suit.rawValue))
                }
            }
            return nil
        }

        /// Every column is in descending rank order, so the cards can simply be played off.
        public var isTriviallySolvable: Bool {
            tableau.allSatisfy { column in zip(column, column.dropFirst()).allSatisfy { $0.rank >= $1.rank } }
        }

        public var canAutoComplete: Bool { !isWon && isTriviallySolvable }

        /// The lowest card that can go to a foundation right now.
        public func autoCompleteMove() -> Move? {
            var best: (Move, Int)?
            for (c, card) in cells.enumerated() {
                if let card, foundationTarget(for: card) != nil, card.rank < (best?.1 ?? 99) {
                    best = (Move(from: .cell(c), to: .foundation(card.suit.rawValue)), card.rank)
                }
            }
            for (t, column) in tableau.enumerated() {
                if let card = column.last, foundationTarget(for: card) != nil, card.rank < (best?.1 ?? 99) {
                    best = (Move(from: .tableau(t), to: .foundation(card.suit.rawValue)), card.rank)
                }
            }
            return best?.0
        }

        /// The same cards in the same places, ignoring the move counter and the order of the free cells.
        public func sameLayout(as other: State) -> Bool {
            tableau == other.tableau && foundations == other.foundations
                && cells.compactMap { $0?.id }.sorted() == other.cells.compactMap { $0?.id }.sorted()
        }

        // MARK: Applying moves

        /// Applies a legal move (returns `nil` and changes nothing otherwise).
        /// `counts` says whether it adds to the move counter (automatic plays don't).
        @discardableResult
        public mutating func apply(_ move: Move, counts: Bool = true) -> Outcome? {
            guard isLegal(move) else { return nil }
            var moved: [Card]
            switch move.from {
            case .cell(let c):
                moved = [cells[c]!]
                cells[c] = nil
            case .tableau(let t):
                moved = Array(tableau[t].suffix(move.count))
                tableau[t].removeLast(move.count)
            case .foundation:
                return nil
            }
            switch move.to {
            case .cell(let c): cells[c] = moved[0]
            case .foundation(let f): foundations[f] += 1
            case .tableau(let t): tableau[t].append(contentsOf: moved)
            }
            if counts { moveCount += 1 }
            return Outcome(move: move, cards: moved)
        }
    }

    /// The shuffle seed of deal `number`.
    static func seed(forDeal number: Int) -> UInt64 {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: number) &* 0x2545_F491_4F6C_DD1D ^ 0xF4EE_CE11)
        return rng.next()
    }

    /// Wraps any integer into 1...maxDeal.
    public static func normalizedDeal(_ number: Int) -> Int {
        ((number - 1) % maxDeal + maxDeal) % maxDeal + 1
    }
}
