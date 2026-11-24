import SwiftUI
import GameLogic

@MainActor @Observable
final class FreeCellModel {
    typealias Logic = FreeCell
    typealias Card = FreeCell.Card

    enum Phase: Equatable {
        /// Looking for a deal the solver can win.
        case preparing
        /// Cards are flying onto the table.
        case dealing
        case playing
        case autoCompleting
        /// Cards cascade off the foundations before the result card appears.
        case celebrating
        case won
    }

    private struct Saved: Codable {
        var state: Logic.State
        var history: [Logic.State]
        var clock: GameClock
    }

    private(set) var state: Logic.State
    private(set) var history: [Logic.State] = []
    private(set) var clock = GameClock()
    private(set) var phase: Phase
    /// Tableau cards dealt so far (drives the deal animation).
    private(set) var dealtCount = 52
    /// Cards that moved last; drawn above everything else so they never slide under a pile.
    private(set) var raisedIDs: Set<Int> = []
    private(set) var hint: Logic.Move?
    /// The solver is looking for a hint.
    private(set) var isThinking = false
    /// A short message shown over the table (hint results, deal notes).
    private(set) var message: String?
    /// Per-card counters; bumping one plays that card's "can't go there" shake.
    private(set) var shakeCounts: [Int: Int] = [:]
    var showStuck = false
    private var stuckDismissed = false
    var reduceMotion = false

    /// Plays cards that are no longer needed on the table to the foundations automatically.
    var autoMove: Bool {
        didSet { UserDefaults.standard.set(autoMove, forKey: Self.autoMoveKey) }
    }

    // Result of the finished game.
    private(set) var finalTime: TimeInterval = 0
    private(set) var isNewBest = false
    private(set) var celebrationStart = Date.now

    /// A winning line from some position: `planStates[i]` is the position before `planMoves[i]`.
    private var planStates: [Logic.State] = []
    private var planMoves: [Logic.Move] = []

    private let store: GameStore
    private let stats: StatsStore
    private var prepareTask: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var hintToken = 0
    private var messageToken = 0
    private var needsDeal: Bool
    private static let autoMoveKey = "freeCell.autoMove"
    let game = GameID.freeCell

    static let cardAnimation = Animation.spring(response: 0.32, dampingFraction: 0.86)

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        UserDefaults.standard.register(defaults: [Self.autoMoveKey: true])
        autoMove = UserDefaults.standard.bool(forKey: Self.autoMoveKey)
        #if DEBUG
        if let scenario = Self.debugScenario() {
            state = scenario
            phase = .playing
            needsDeal = false
            return
        }
        #endif
        if let saved = store.load(Saved.self, key: GameID.freeCell.saveKey), !saved.state.isWon {
            state = saved.state
            history = saved.history
            clock = saved.clock
            phase = .playing
            needsDeal = false
        } else {
            // A placeholder until `start()` has found a winnable deal; nothing is shown meanwhile.
            state = .deal(number: 1)
            phase = .preparing
            dealtCount = 0
            needsDeal = true
        }
    }

    // MARK: - Derived

    var isInteractive: Bool { phase == .playing && !showStuck }
    var canUndo: Bool { phase == .playing && !history.isEmpty }
    var canRestart: Bool { phase == .playing && (state.moveCount > 0 || !history.isEmpty) }
    var canAutoComplete: Bool { phase == .playing && state.canAutoComplete }
    var bestTime: TimeInterval? { stats.stats(for: game).bestTime }
    var winStreak: Int { stats.stats(for: game).currentStreak }

    /// Cards lifted together when grabbing `card`, or `nil` if it can't be picked up.
    func liftedCards(for card: Card) -> [Card]? {
        guard isInteractive, let (pile, index) = state.location(of: card),
              let count = state.pickUpCount(pile: pile, index: index) else { return nil }
        return Array(state.cards(in: pile).suffix(count))
    }

    func legalMoves(for card: Card) -> [Logic.Move] {
        guard isInteractive, let (pile, index) = state.location(of: card) else { return [] }
        return state.moves(forCardAt: pile, index: index)
    }

    func shakeCount(_ id: Int) -> Int { shakeCounts[id] ?? 0 }

    // MARK: - Starting

    /// Deals the first game if there is nothing to resume. Called when the screen appears.
    func start() {
        guard needsDeal, prepareTask == nil else { return }
        needsDeal = false
        prepare(from: Self.debugDeal() ?? Self.randomDeal())
    }

    /// Deals a new game, starting from deal `number` (a random one by default). An abandoned
    /// game with progress counts as a loss.
    func newGame(number: Int? = nil) {
        if phase != .won && phase != .celebrating && phase != .preparing && state.moveCount > 0 {
            stats.record(game, won: false, time: clock.elapsed())
        }
        store.remove(key: game.saveKey)
        resetPlay()
        withAnimation(.easeInOut(duration: 0.3)) {
            dealtCount = 0
            phase = .preparing
        }
        needsDeal = false
        prepare(from: number ?? Self.randomDeal(), requested: number)
    }

    /// Starts this deal over from the beginning.
    func restartDeal() {
        guard canRestart else { return }
        let deal = Logic.State.deal(number: state.deal)
        store.remove(key: game.saveKey)
        resetPlay()
        withAnimation(Self.cardAnimation) {
            state = deal
        }
        Feedback.play(.flip)
    }

    private func resetPlay() {
        autoTask?.cancel()
        hintTask?.cancel()
        history = []
        hint = nil
        isThinking = false
        showStuck = false
        stuckDismissed = false
        clock = GameClock()
        raisedIDs = []
        planStates = []
        planMoves = []
    }

    private static func randomDeal() -> Int { Int.random(in: 1...Logic.maxDeal) }

    private func prepare(from number: Int, requested: Int? = nil) {
        prepareTask?.cancel()
        prepareTask = Task { [weak self] in
            let found = await Self.findDeal(from: number)
            guard !Task.isCancelled, let self else { return }
            self.prepareTask = nil
            guard let found else {
                // Practically impossible (200 deals in a row the solver can't win): try elsewhere.
                self.prepare(from: Self.randomDeal())
                return
            }
            if let requested, found.state.deal != requested {
                self.show("Deal #\(requested) couldn't be verified, so here's #\(found.state.deal).")
            }
            self.state = found.state
            self.storePlan(from: found.state, moves: found.solution)
            await self.animateDeal()
        }
    }

    nonisolated private static func findDeal(from number: Int) async -> (state: Logic.State, solution: [Logic.Move])? {
        await Task.detached(priority: .userInitiated) {
            Logic.solvableDeal(startingAt: number) { !Task.isCancelled }
        }.value
    }

    private func animateDeal() async {
        phase = .dealing
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { dealtCount = 52 }
        } else {
            for i in stride(from: 2, through: 52, by: 2) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { dealtCount = i }
                try? await Task.sleep(for: .milliseconds(24))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled else { return }
        dealtCount = 52
        phase = .playing
    }

    /// Deal order of a tableau card (row by row, left to right).
    static func dealIndex(column: Int, row: Int) -> Int { row * Logic.columnCount + column }

    // MARK: - Moves

    /// Sends a tapped card to its best destination, or shakes it if there is none.
    func tap(_ card: Card) {
        guard isInteractive else { return }
        finishAutoMoves()
        guard let (pile, index) = state.location(of: card) else { return }
        if let move = state.bestMove(forCardAt: pile, index: index) {
            perform(move)
            return
        }
        let count = state.cards(in: pile).count - index
        reject(state.cards(in: pile).suffix(count))
        let limit = state.maxMovable(toEmptyColumn: false)
        if count > limit, state.pickUpCount(pile: pile, index: index) != nil {
            show("With these free cells and columns, you can move \(limit) \(limit == 1 ? "card" : "cards") at once.")
        }
    }

    /// Drops the run headed by `card` on `target`. Returns whether the move happened.
    @discardableResult
    func drop(_ card: Card, on target: Logic.Pile) -> Bool {
        guard isInteractive else { return false }
        finishAutoMoves()
        guard let (pile, index) = state.location(of: card),
              let count = state.pickUpCount(pile: pile, index: index) else { return false }
        return perform(Logic.Move(from: pile, to: target, count: count))
    }

    func reject<C: Sequence>(_ cards: C) where C.Element == Card {
        for card in cards { shakeCounts[card.id, default: 0] += 1 }
        Feedback.play(.invalid)
    }

    @discardableResult
    func perform(_ move: Logic.Move) -> Bool {
        guard isInteractive else { return false }
        finishAutoMoves()
        let previous = state
        guard let outcome = state.apply(move) else { return false }
        history.append(previous)
        raisedIDs = Set(outcome.cards.map(\.id))
        clearHint()
        clock.start()
        playFeedback(for: move)
        if autoMove, state.nextSafeMove() != nil {
            runAutoMoves()
        } else {
            afterMove()
        }
        return true
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        autoTask?.cancel()
        autoTask = nil
        raisedIDs = Self.movedCards(from: state, to: previous)
        state = previous
        clearHint()
        showStuck = false
        stuckDismissed = false
        Feedback.play(.tap)
        persist()
    }

    /// Plays safe cards to the foundations one after another (each one animated).
    private func runAutoMoves() {
        autoTask?.cancel()
        autoTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(self.reduceMotion ? 60 : 130))
                guard !Task.isCancelled, let move = self.state.nextSafeMove() else { break }
                withAnimation(self.reduceMotion ? .easeOut(duration: 0.12) : Self.cardAnimation) {
                    if let outcome = self.state.apply(move, counts: false) {
                        self.raisedIDs = Set(outcome.cards.map(\.id))
                    }
                }
                Feedback.play(.pop)
                if self.state.nextSafeMove() == nil { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.autoTask = nil
            self.afterMove()
        }
    }

    /// Plays any pending automatic moves at once (before the player's next action).
    private func finishAutoMoves() {
        guard let task = autoTask else { return }
        task.cancel()
        autoTask = nil
        while let move = state.nextSafeMove() {
            if let outcome = state.apply(move, counts: false) { raisedIDs.formUnion(outcome.cards.map(\.id)) }
        }
        afterMove()
    }

    func setAutoMove(_ on: Bool) {
        autoMove = on
        Feedback.play(.select)
        if on, isInteractive, state.nextSafeMove() != nil { runAutoMoves() }
    }

    // MARK: - Hint

    func showHint() {
        guard isInteractive, !isThinking else { return }
        finishAutoMoves()
        guard isInteractive else { return }
        if let move = plannedMove() {
            present(hint: move)
            return
        }
        isThinking = true
        let start = state
        hintTask = Task { [weak self] in
            let result = await Self.solve(start)
            guard let self, !Task.isCancelled else { return }
            self.isThinking = false
            guard self.state == start, self.isInteractive else { return }
            if result.solved, let first = result.moves.first {
                self.storePlan(from: start, moves: result.moves)
                self.present(hint: first)
            } else {
                Feedback.play(.invalid)
                self.show(result.status == .unsolvable
                          ? "There's no way to win from here. Try Undo."
                          : "No winning line found from here. Try Undo.")
            }
        }
    }

    nonisolated private static func solve(_ state: Logic.State) async -> Logic.Solver.Result {
        await Task.detached(priority: .userInitiated) { Logic.Solver.solve(state) }.value
    }

    /// The next move of the stored winning line, if the table is still on it.
    private func plannedMove() -> Logic.Move? {
        guard let i = planStates.lastIndex(where: {
            $0.tableau == state.tableau && $0.cells == state.cells && $0.foundations == state.foundations
        }) else { return nil }
        let move = planMoves[i]
        return state.isLegal(move) ? move : nil
    }

    private func storePlan(from start: Logic.State, moves: [Logic.Move]) {
        var s = start
        var states: [Logic.State] = []
        for move in moves {
            states.append(s)
            guard s.apply(move) != nil else { break }
        }
        planStates = states
        planMoves = Array(moves.prefix(states.count))
    }

    private func present(hint move: Logic.Move) {
        withAnimation(.easeOut(duration: 0.2)) { hint = move }
        Feedback.play(.select)
        AccessibilityNotification.Announcement("Hint: \(describe(move))").post()
        hintToken += 1
        let token = hintToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.hintToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.hint = nil }
        }
    }

    private func clearHint() {
        hintTask?.cancel()
        isThinking = false
        hint = nil
        hintToken += 1
    }

    /// Spoken description of a move, e.g. "move 7 of Hearts onto 8 of Clubs".
    func describe(_ move: Logic.Move) -> String {
        let cards = state.cards(in: move.from)
        let lead = cards.count >= move.count ? cards[cards.count - move.count] : nil
        let what = move.count > 1 ? "move \(move.count) cards from \(lead?.name ?? "")" : "move \(lead?.name ?? "the card")"
        switch move.to {
        case .foundation: return "\(what) to its foundation"
        case .cell: return "\(what) to a free cell"
        case .tableau(let t):
            return state.tableau[t].last.map { "\(what) onto \($0.name)" } ?? "\(what) to empty column \(t + 1)"
        }
    }

    func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { message = text }
        AccessibilityNotification.Announcement(text).post()
        messageToken += 1
        let token = messageToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard let self, self.messageToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.message = nil }
        }
    }

    // MARK: - Auto-complete & end of game

    func autoComplete() {
        guard canAutoComplete else { return }
        finishAutoMoves()
        guard canAutoComplete else { return }
        phase = .autoCompleting
        clearHint()
        clock.start()
        Task { @MainActor [weak self] in
            while let self, self.phase == .autoCompleting {
                guard let move = self.state.autoCompleteMove() else { break }
                withAnimation(self.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.9)) {
                    if let outcome = self.state.apply(move, counts: false) {
                        self.raisedIDs = Set(outcome.cards.map(\.id))
                    }
                }
                if self.state.foundationCount % 4 == 0 { Haptics.tap() }
                try? await Task.sleep(for: .milliseconds(self.reduceMotion ? 40 : 80))
            }
            guard let self, self.phase == .autoCompleting else { return }
            self.phase = .playing
            self.afterMove()
        }
    }

    func dismissStuck() {
        showStuck = false
        stuckDismissed = true
        clock.start()
    }

    func finishCelebration() {
        guard phase == .celebrating else { return }
        withAnimation(.easeOut(duration: 0.3)) { phase = .won }
    }

    func setActive(_ active: Bool) {
        if active, phase == .playing || phase == .autoCompleting, !showStuck, state.moveCount > 0 {
            clock.start()
        } else {
            clock.pause()
        }
        if !active {
            if autoTask != nil { finishAutoMoves() }
            persist()
        }
    }

    private func afterMove() {
        if state.isWon {
            win()
            return
        }
        if state.isStuck {
            if !stuckDismissed {
                showStuck = true
                clock.pause()
                Feedback.play(.lose)
            }
        } else {
            stuckDismissed = false
        }
        persist()
    }

    private func win() {
        guard phase == .playing || phase == .autoCompleting else { return }
        clock.pause()
        finalTime = clock.elapsed()
        isNewBest = bestTime.map { finalTime < $0 } ?? true
        stats.record(game, won: true, time: finalTime)
        store.remove(key: game.saveKey)
        clearHint()
        Feedback.play(.win)
        celebrationStart = .now
        withAnimation(.easeOut(duration: 0.2)) {
            phase = reduceMotion ? .won : .celebrating
        }
    }

    // MARK: - Private

    private static func movedCards(from a: Logic.State, to b: Logic.State) -> Set<Int> {
        Set(Card.deck.filter { a.location(of: $0)?.pile != b.location(of: $0)?.pile }.map(\.id))
    }

    private func playFeedback(for move: Logic.Move) {
        switch move.to {
        case .foundation: Feedback.play(.pop)
        case .cell: Feedback.play(.move)
        case .tableau: Feedback.play(.place)
        }
    }

    private func persist() {
        guard phase == .playing || phase == .autoCompleting else { return }
        guard state.moveCount > 0 else {
            // Undone back to the deal: nothing worth resuming.
            store.remove(key: game.saveKey)
            return
        }
        store.save(Saved(state: state, history: history, clock: clock), key: game.saveKey)
    }

    // MARK: - Debug

    /// `-freeCellDeal <n>` deals (the first winnable deal from) number n, for tests and screenshots.
    private static func debugDeal() -> Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-freeCellDeal"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return nil
    }

    #if DEBUG
    /// `-freeCellScenario nearlySolved`: everything up to the 8s is home and four columns hold
    /// King down to 9. Playing any 9 lets the rest go up automatically.
    private static func debugScenario() -> Logic.State? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-freeCellScenario"), i + 1 < args.count,
              args[i + 1] == "nearlySolved" else { return nil }
        let pairs: [(Logic.Suit, Logic.Suit)] = [(.spades, .hearts), (.hearts, .spades), (.diamonds, .clubs), (.clubs, .diamonds)]
        var columns: [[Card]] = pairs.map { a, b in
            (9...13).reversed().map { Card($0, $0 % 2 == 1 ? a : b) }
        }
        columns += [[], [], [], []]
        return Logic.State(deal: 1, tableau: columns, foundations: [8, 8, 8, 8], moveCount: 0)
    }
    #endif
}
