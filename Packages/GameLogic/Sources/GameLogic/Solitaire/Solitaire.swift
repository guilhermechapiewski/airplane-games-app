/// Klondike solitaire: build four suit piles from Ace to King using a seven-column
/// tableau, a stock and a waste pile.
public enum Solitaire {

    // MARK: - Cards

    public enum Suit: Int, CaseIterable, Codable, Sendable {
        case spades, hearts, diamonds, clubs

        public var isRed: Bool { self == .hearts || self == .diamonds }

        public var name: String {
            switch self {
            case .spades: "Spades"
            case .hearts: "Hearts"
            case .diamonds: "Diamonds"
            case .clubs: "Clubs"
            }
        }

        public var symbol: String {
            switch self {
            case .spades: "♠"
            case .hearts: "♥"
            case .diamonds: "♦"
            case .clubs: "♣"
            }
        }
    }

    public struct Card: Hashable, Sendable, Identifiable, CustomStringConvertible {
        /// 1 (Ace) ... 13 (King).
        public let rank: Int
        public let suit: Suit

        public init(_ rank: Int, _ suit: Suit) {
            precondition((1...13).contains(rank), "rank out of range")
            self.rank = rank
            self.suit = suit
        }

        /// Recreates a card from its `id` (0...51).
        public init?(id: Int) {
            guard (0..<52).contains(id), let suit = Suit(rawValue: id / 13) else { return nil }
            self.init(id % 13 + 1, suit)
        }

        /// Stable identity, unique within a deck (0...51).
        public var id: Int { suit.rawValue * 13 + rank - 1 }
        public var isRed: Bool { suit.isRed }
        public var isKing: Bool { rank == 13 }

        public var rankSymbol: String {
            switch rank {
            case 1: "A"
            case 11: "J"
            case 12: "Q"
            case 13: "K"
            default: "\(rank)"
            }
        }

        public var rankName: String {
            switch rank {
            case 1: "Ace"
            case 11: "Jack"
            case 12: "Queen"
            case 13: "King"
            default: "\(rank)"
            }
        }

        /// Spoken name, e.g. "7 of Hearts".
        public var name: String { "\(rankName) of \(suit.name)" }
        public var description: String { rankSymbol + suit.symbol }

        /// Whether this card may be placed on `other` in the tableau
        /// (one rank lower, opposite color).
        public func canStack(on other: Card) -> Bool {
            other.rank == rank + 1 && other.isRed != isRed
        }

        /// A full, ordered 52-card deck.
        public static let deck: [Card] = (0..<52).compactMap { Card(id: $0) }
    }

    // MARK: - Rules vocabulary

    public enum DrawMode: String, CaseIterable, Codable, Sendable, Identifiable {
        case draw1, draw3

        public var id: String { rawValue }
        public var cardsPerDraw: Int { self == .draw1 ? 1 : 3 }
        public var title: String { self == .draw1 ? "Draw 1" : "Draw 3" }
        /// Points lost when the waste is turned back into the stock.
        public var recyclePenalty: Int { self == .draw1 ? 100 : 20 }
    }

    /// A place cards can live.
    public enum Pile: Hashable, Codable, Sendable {
        case stock
        case waste
        case foundation(Int)
        case tableau(Int)
    }

    /// A move of `count` cards from the top of one pile to another.
    /// Stock → waste is a draw; waste → stock turns the waste over.
    public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
        public var from: Pile
        public var to: Pile
        public var count: Int

        public init(from: Pile, to: Pile, count: Int = 1) {
            self.from = from
            self.to = to
            self.count = count
        }

        public static let draw = Move(from: .stock, to: .waste)
        public static let recycle = Move(from: .waste, to: .stock)

        public var isStockMove: Bool { from == .stock || to == .stock }

        public var description: String { "\(from)→\(to)×\(count)" }
    }

    /// One of the seven tableau columns. Cards are ordered bottom → top; the
    /// first `faceDownCount` are face down.
    public struct Column: Hashable, Codable, Sendable {
        public internal(set) var cards: [Card]
        public internal(set) var faceDownCount: Int

        public init(cards: [Card] = [], faceDownCount: Int = 0) {
            self.cards = cards
            self.faceDownCount = min(max(0, faceDownCount), max(0, cards.count - 1))
        }

        public var isEmpty: Bool { cards.isEmpty }
        public var top: Card? { cards.last }
        public var faceUpCount: Int { cards.count - faceDownCount }
        public var faceUpCards: ArraySlice<Card> { cards[faceDownCount...] }
        public func isFaceUp(_ index: Int) -> Bool { index >= faceDownCount && index < cards.count }
    }

    /// What a move did, for animation, sound and scoring feedback.
    public struct Outcome: Equatable, Sendable {
        public var move: Move
        /// The cards that travelled (drawn cards for a draw, the whole waste for a recycle).
        public var cards: [Card]
        /// A tableau card that was turned face up by this move.
        public var flipped: Card?
        public var scoreDelta: Int
    }

    /// Standard (Windows-style) scoring.
    public enum Scoring {
        public static let wasteToTableau = 5
        public static let toFoundation = 10
        public static let flip = 5
        public static let foundationToTableau = -15

        /// Bonus awarded when a game is won, rewarding fast play (none under 30 s).
        public static func timeBonus(seconds: Double) -> Int {
            guard seconds >= 30 else { return 0 }
            return Int(700_000 / seconds.rounded(.down))
        }
    }

    // MARK: - Game state

    public struct State: Codable, Equatable, Sendable {
        public let drawMode: DrawMode
        /// Face-down stock; the last element is the top card.
        public internal(set) var stock: [Card]
        /// Face-up waste; the last element is the playable card.
        public internal(set) var waste: [Card]
        /// How many top waste cards are fanned out (Draw 3 shows up to three).
        public internal(set) var wasteFan: Int
        public internal(set) var foundations: [[Card]]
        public internal(set) var tableau: [Column]
        public internal(set) var score: Int
        public internal(set) var moveCount: Int
        /// Times the waste has been turned back into the stock.
        public internal(set) var passes: Int

        public init(drawMode: DrawMode, stock: [Card], waste: [Card] = [], foundations: [[Card]] = [[], [], [], []],
                    tableau: [Column], score: Int = 0) {
            self.drawMode = drawMode
            self.stock = stock
            self.waste = waste
            self.wasteFan = min(waste.count, drawMode.cardsPerDraw)
            self.foundations = foundations
            self.tableau = tableau
            self.score = score
            self.moveCount = 0
            self.passes = 0
        }

        /// A standard Klondike deal from a deterministic shuffle.
        public static func deal(drawMode: DrawMode, seed: UInt64) -> State {
            let deck = Solitaire.shuffledDeck(seed: seed)
            var columns = Array(repeating: [Card](), count: 7)
            var index = 0
            for row in 0..<7 {
                for col in row..<7 {
                    columns[col].append(deck[index])
                    index += 1
                }
            }
            let tableau = columns.enumerated().map { Column(cards: $1, faceDownCount: $0) }
            return State(drawMode: drawMode, stock: Array(deck[index...]), tableau: tableau)
        }

        // MARK: Queries

        public var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }
        public var foundationCount: Int { foundations.reduce(0) { $0 + $1.count } }
        public var canDraw: Bool { !stock.isEmpty || !waste.isEmpty }
        public var allFaceUp: Bool { tableau.allSatisfy { $0.faceDownCount == 0 } }

        public func cards(in pile: Pile) -> [Card] {
            switch pile {
            case .stock: stock
            case .waste: waste
            case .foundation(let f): foundations.indices.contains(f) ? foundations[f] : []
            case .tableau(let t): tableau.indices.contains(t) ? tableau[t].cards : []
            }
        }

        public func top(of pile: Pile) -> Card? { cards(in: pile).last }

        /// Where a card currently is: its pile and index within it (bottom = 0).
        public func location(of card: Card) -> (pile: Pile, index: Int)? {
            if let i = stock.firstIndex(of: card) { return (.stock, i) }
            if let i = waste.firstIndex(of: card) { return (.waste, i) }
            for (f, pile) in foundations.enumerated() {
                if let i = pile.firstIndex(of: card) { return (.foundation(f), i) }
            }
            for (t, column) in tableau.enumerated() {
                if let i = column.cards.firstIndex(of: card) { return (.tableau(t), i) }
            }
            return nil
        }

        public func isFaceUp(_ card: Card) -> Bool {
            guard let (pile, index) = location(of: card) else { return false }
            switch pile {
            case .stock: return false
            case .waste, .foundation: return true
            case .tableau(let t): return tableau[t].isFaceUp(index)
            }
        }

        /// The foundation a card can be played to right now, if any.
        public func foundationTarget(for card: Card) -> Int? {
            if card.rank == 1 { return foundations.firstIndex(where: \.isEmpty) }
            return foundations.firstIndex { $0.last?.suit == card.suit && $0.last?.rank == card.rank - 1 }
        }

        public func canPlace(_ card: Card, onFoundation f: Int) -> Bool {
            guard foundations.indices.contains(f) else { return false }
            guard let top = foundations[f].last else { return card.rank == 1 }
            return top.suit == card.suit && top.rank + 1 == card.rank
        }

        public func canPlace(_ card: Card, onTableau t: Int) -> Bool {
            guard tableau.indices.contains(t) else { return false }
            guard let top = tableau[t].top else { return card.isKing }
            return card.canStack(on: top)
        }

        /// The cards a move would pick up, or `nil` if they can't be picked up together.
        func movingCards(from pile: Pile, count: Int) -> ArraySlice<Card>? {
            guard count >= 1 else { return nil }
            switch pile {
            case .stock:
                return nil
            case .waste:
                guard count == 1, !waste.isEmpty else { return nil }
                return waste.suffix(1)
            case .foundation(let f):
                guard count == 1, foundations.indices.contains(f), !foundations[f].isEmpty else { return nil }
                return foundations[f].suffix(1)
            case .tableau(let t):
                guard tableau.indices.contains(t), count <= tableau[t].faceUpCount else { return nil }
                let run = tableau[t].cards.suffix(count)
                return Solitaire.isRun(run) ? run : nil
            }
        }

        public func isLegal(_ move: Move) -> Bool {
            switch (move.from, move.to) {
            case (.stock, .waste): return !stock.isEmpty
            case (.waste, .stock): return stock.isEmpty && !waste.isEmpty
            case (.stock, _), (_, .stock), (_, .waste): return false
            default: break
            }
            guard let moving = movingCards(from: move.from, count: move.count), let lead = moving.first else { return false }
            switch move.to {
            case .foundation(let f):
                if case .foundation = move.from { return false }
                return moving.count == 1 && canPlace(lead, onFoundation: f)
            case .tableau(let t):
                if case .tableau(let s) = move.from, s == t { return false }
                return canPlace(lead, onTableau: t)
            case .stock, .waste:
                return false
            }
        }

        /// Every legal move, including drawing or turning over the stock.
        public func legalMoves() -> [Move] {
            var moves: [Move] = []
            if !stock.isEmpty { moves.append(.draw) } else if !waste.isEmpty { moves.append(.recycle) }
            var sources: [(Pile, Int)] = []
            if !waste.isEmpty { sources.append((.waste, 1)) }
            for (t, column) in tableau.enumerated() where column.faceUpCount > 0 {
                for n in 1...column.faceUpCount { sources.append((.tableau(t), n)) }
            }
            for (f, pile) in foundations.enumerated() where !pile.isEmpty { sources.append((.foundation(f), 1)) }
            let targets = (0..<4).map(Pile.foundation) + (0..<7).map(Pile.tableau)
            for (pile, n) in sources {
                for target in targets {
                    let move = Move(from: pile, to: target, count: n)
                    if isLegal(move) { moves.append(move) }
                }
            }
            return moves
        }

        /// Legal moves that pick up the card at `index` of `pile` (and any cards above it).
        public func moves(forCardAt pile: Pile, index: Int) -> [Move] {
            guard let count = pickUpCount(pile: pile, index: index) else { return [] }
            let targets = (0..<4).map(Pile.foundation) + (0..<7).map(Pile.tableau)
            return targets.map { Move(from: pile, to: $0, count: count) }.filter(isLegal)
        }

        /// How many cards would be lifted when grabbing the card at `index` of `pile`.
        public func pickUpCount(pile: Pile, index: Int) -> Int? {
            let count = cards(in: pile).count - index
            guard index >= 0, count >= 1, pile != .stock else { return nil }
            return movingCards(from: pile, count: count) == nil ? nil : count
        }

        /// The most useful destination for a tapped card: a foundation if possible,
        /// otherwise a tableau column (preferring one that already has cards).
        public func bestMove(forCardAt pile: Pile, index: Int) -> Move? {
            guard let count = pickUpCount(pile: pile, index: index) else { return nil }
            let lead = cards(in: pile)[index]
            if count == 1, let f = foundationTarget(for: lead) {
                if case .foundation = pile {} else { return Move(from: pile, to: .foundation(f)) }
            }
            var emptyTarget: Move?
            for t in tableau.indices {
                let move = Move(from: pile, to: .tableau(t), count: count)
                guard isLegal(move) else { continue }
                if tableau[t].isEmpty {
                    // Moving a King that already heads its column to another empty column achieves nothing.
                    if case .tableau = pile, index == 0 { continue }
                    if emptyTarget == nil { emptyTarget = move }
                } else {
                    return move
                }
            }
            return emptyTarget
        }

        // MARK: Hints

        /// A tableau column the card can go on, preferring non-empty columns.
        func tableauTarget(for card: Card, excluding: Int? = nil, allowEmpty: Bool = true) -> Int? {
            var empty: Int?
            for t in tableau.indices where t != excluding && canPlace(card, onTableau: t) {
                if !tableau[t].isEmpty { return t }
                if allowEmpty, empty == nil { empty = t }
            }
            return empty
        }

        /// A productive move, or `nil` when nothing useful remains.
        ///
        /// Order: foundation plays, moves that reveal a hidden card, waste plays,
        /// moves that free a card for a foundation, clearing a column for a King,
        /// then drawing from the stock if any stock card could be used.
        public func hint() -> Move? {
            for (t, column) in tableau.enumerated() {
                if let top = column.top, let f = foundationTarget(for: top) {
                    return Move(from: .tableau(t), to: .foundation(f))
                }
            }
            if let card = waste.last, let f = foundationTarget(for: card) {
                return Move(from: .waste, to: .foundation(f))
            }
            for (t, column) in tableau.enumerated() where column.faceDownCount > 0 {
                let lead = column.cards[column.faceDownCount]
                if let target = tableauTarget(for: lead, excluding: t) {
                    return Move(from: .tableau(t), to: .tableau(target), count: column.faceUpCount)
                }
            }
            if let card = waste.last, let target = tableauTarget(for: card) {
                return Move(from: .waste, to: .tableau(target))
            }
            for (t, column) in tableau.enumerated() where column.faceUpCount > 1 {
                for i in (column.faceDownCount + 1)..<column.cards.count where foundationTarget(for: column.cards[i - 1]) != nil {
                    if let target = tableauTarget(for: column.cards[i], excluding: t, allowEmpty: false) {
                        return Move(from: .tableau(t), to: .tableau(target), count: column.cards.count - i)
                    }
                }
            }
            let reachable = canDraw ? reachableStockCards() : []
            if kingIsWaiting(reachable: reachable) {
                for (t, column) in tableau.enumerated() where column.faceDownCount == 0 && !column.isEmpty && !column.cards[0].isKing {
                    if let target = tableauTarget(for: column.cards[0], excluding: t, allowEmpty: false) {
                        return Move(from: .tableau(t), to: .tableau(target), count: column.cards.count)
                    }
                }
            }
            let useful = reachable.contains { card in
                card != waste.last && (foundationTarget(for: card) != nil || tableauTarget(for: card) != nil)
            }
            if useful { return stock.isEmpty ? .recycle : .draw }
            return nil
        }

        /// No productive move remains (see `hint()`).
        public var isStuck: Bool { !isWon && hint() == nil }

        /// A King that would benefit from an empty column.
        private func kingIsWaiting(reachable: [Card]) -> Bool {
            if tableau.contains(where: { $0.faceDownCount > 0 && $0.cards[$0.faceDownCount].isKing }) { return true }
            return reachable.contains(where: \.isKing)
        }

        /// Every card that can become the playable waste card by drawing (and
        /// turning the stock over) without playing anything else.
        public func reachableStockCards() -> [Card] {
            var stock = self.stock
            var waste = self.waste
            var seen: [Card] = waste.last.map { [$0] } ?? []
            var seenIDs = Set(seen.map(\.id))
            let per = drawMode.cardsPerDraw
            for _ in 0..<2 {
                while !stock.isEmpty {
                    let n = min(per, stock.count)
                    waste.append(contentsOf: stock.suffix(n).reversed())
                    stock.removeLast(n)
                    if let top = waste.last, seenIDs.insert(top.id).inserted { seen.append(top) }
                }
                stock = waste.reversed()
                waste = []
            }
            return seen
        }

        // MARK: Auto-complete

        /// Every tableau card is face up, so the game can be finished automatically.
        public var canAutoComplete: Bool { !isWon && allFaceUp }

        /// Plays the lowest-ranked card that can go to a foundation, taking it from
        /// the tableau, the waste or (when finishing) directly from the stock.
        @discardableResult
        public mutating func autoCompleteStep() -> Outcome? {
            guard canAutoComplete else { return nil }
            var best: (pile: Pile, index: Int, card: Card, foundation: Int)?
            func consider(_ pile: Pile, _ index: Int, _ card: Card) {
                guard let f = foundationTarget(for: card), card.rank < (best?.card.rank ?? 99) else { return }
                best = (pile, index, card, f)
            }
            for (t, column) in tableau.enumerated() {
                if let top = column.top { consider(.tableau(t), column.cards.count - 1, top) }
            }
            for (i, card) in waste.enumerated() { consider(.waste, i, card) }
            for (i, card) in stock.enumerated() { consider(.stock, i, card) }
            guard let best else { return nil }
            switch best.pile {
            case .tableau(let t): tableau[t].cards.removeLast()
            case .waste: waste.remove(at: best.index)
            case .stock: stock.remove(at: best.index)
            case .foundation: return nil
            }
            wasteFan = min(wasteFan, waste.count)
            if wasteFan == 0, !waste.isEmpty { wasteFan = 1 }
            foundations[best.foundation].append(best.card)
            let before = score
            score += Scoring.toFoundation
            moveCount += 1
            return Outcome(move: Move(from: best.pile, to: .foundation(best.foundation)),
                           cards: [best.card], flipped: nil, scoreDelta: score - before)
        }

        // MARK: Applying moves

        /// Applies a move. Returns `nil` (and leaves the state untouched) if it's illegal.
        @discardableResult
        public mutating func apply(_ move: Move) -> Outcome? {
            guard isLegal(move) else { return nil }
            var outcome = Outcome(move: move, cards: [], flipped: nil, scoreDelta: 0)
            var delta = 0
            switch (move.from, move.to) {
            case (.stock, .waste):
                let n = min(drawMode.cardsPerDraw, stock.count)
                // The drawn group is turned over, so the stock's top card ends up underneath.
                let drawn = Array(stock.suffix(n).reversed())
                stock.removeLast(n)
                waste.append(contentsOf: drawn)
                wasteFan = n
                outcome.cards = drawn
            case (.waste, .stock):
                outcome.cards = waste
                stock = waste.reversed()
                waste = []
                wasteFan = 0
                passes += 1
                delta -= drawMode.recyclePenalty
            default:
                let cards = take(move.count, from: move.from)
                switch move.to {
                case .foundation(let f): foundations[f].append(contentsOf: cards)
                case .tableau(let t): tableau[t].cards.append(contentsOf: cards)
                case .stock, .waste: break
                }
                outcome.cards = cards
                delta += Self.points(from: move.from, to: move.to)
                if case .tableau(let t) = move.from, let flipped = flipIfNeeded(t) {
                    outcome.flipped = flipped
                    delta += Scoring.flip
                }
            }
            let before = score
            score = max(0, score + delta)
            outcome.scoreDelta = score - before
            moveCount += 1
            return outcome
        }

        /// Draws from the stock, or turns the waste over when the stock is empty.
        @discardableResult
        public mutating func drawOrRecycle() -> Outcome? {
            apply(stock.isEmpty ? .recycle : .draw)
        }

        private mutating func take(_ count: Int, from pile: Pile) -> [Card] {
            switch pile {
            case .stock:
                return []
            case .waste:
                let card = waste.removeLast()
                wasteFan = waste.isEmpty ? 0 : max(1, wasteFan - 1)
                return [card]
            case .foundation(let f):
                return [foundations[f].removeLast()]
            case .tableau(let t):
                let cards = Array(tableau[t].cards.suffix(count))
                tableau[t].cards.removeLast(count)
                return cards
            }
        }

        private mutating func flipIfNeeded(_ t: Int) -> Card? {
            guard tableau[t].faceDownCount > 0, tableau[t].faceDownCount == tableau[t].cards.count else { return nil }
            tableau[t].faceDownCount -= 1
            return tableau[t].top
        }

        static func points(from: Pile, to: Pile) -> Int {
            switch (from, to) {
            case (.waste, .tableau): Scoring.wasteToTableau
            case (.waste, .foundation), (.tableau, .foundation): Scoring.toFoundation
            case (.foundation, .tableau): Scoring.foundationToTableau
            default: 0
            }
        }
    }

    // MARK: - Helpers

    /// Whether the cards form a descending, alternating-color sequence.
    public static func isRun<C: Collection>(_ cards: C) -> Bool where C.Element == Card {
        zip(cards, cards.dropFirst()).allSatisfy { $1.canStack(on: $0) }
    }

    /// A deterministic Fisher–Yates shuffle of a full deck.
    public static func shuffledDeck(seed: UInt64) -> [Card] {
        var rng = SeededRandom(seed: seed)
        var deck = Card.deck
        for i in stride(from: deck.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            deck.swapAt(i, j)
        }
        return deck
    }
}

extension Solitaire.Card: Codable {
    // Encoded compactly as its id so saves (with long undo histories) stay small.
    public init(from decoder: Decoder) throws {
        let id = try decoder.singleValueContainer().decode(Int.self)
        guard let card = Solitaire.Card(id: id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid card id \(id)"))
        }
        self = card
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}
