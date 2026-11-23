import SwiftUI
import GameLogic

@MainActor @Observable
final class SolitaireModel {
    typealias Logic = Solitaire
    typealias Card = Solitaire.Card

    enum Phase: Equatable {
        /// Looking for a winnable deal.
        case preparing
        /// Cards are flying from the stock to the tableau.
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
        var provenWinnable: Bool
    }

    private(set) var state: Logic.State
    private(set) var history: [Logic.State] = []
    private(set) var clock = GameClock()
    private(set) var phase: Phase
    private(set) var provenWinnable = false
    /// Number of tableau cards dealt so far (drives the deal animation).
    private(set) var dealtCount = 28
    /// Cards that moved last; drawn above everything else so they never slide under a pile.
    private(set) var raisedIDs: Set<Int> = []
    private(set) var hint: Logic.Move?
    /// Per-card counters; bumping one plays that card's "can't go there" shake.
    private(set) var shakeCounts: [Int: Int] = [:]
    /// Bumped by every state change so views can animate in sync.
    private(set) var revision = 0
    var showStuck = false
    private var stuckDismissed = false
    var reduceMotion = false

    // Result of the finished game.
    private(set) var finalScore = 0
    private(set) var timeBonus = 0
    private(set) var finalTime: TimeInterval = 0
    private(set) var isNewBest = false
    private(set) var celebrationStart = Date.now

    private let store: GameStore
    private let stats: StatsStore
    private var prepareTask: Task<Void, Never>?
    private var hintToken = 0
    private static let maxUndo = 250
    private static let modeKey = "solitaire.drawMode"
    let game = GameID.solitaire

    static let cardAnimation = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Today, when this is the daily deal (draw 1, fixed by the date, saved separately).
    let daily: Daily.Day?
    private var saveKey: String { daily.map { game.dailySaveKey($0) } ?? game.saveKey }

    init(daily: Daily.Day? = nil, store: GameStore = .shared, stats: StatsStore = .shared) {
        self.daily = daily
        self.store = store
        self.stats = stats
        #if DEBUG
        if let scenario = Self.debugScenario() {
            state = scenario
            phase = .playing
            if ProcessInfo.processInfo.arguments.contains("autowin") {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.autoComplete()
                }
            }
            return
        }
        #endif
        if let saved = store.load(Saved.self, key: daily.map { GameID.solitaire.dailySaveKey($0) } ?? GameID.solitaire.saveKey),
           !saved.state.isWon {
            state = saved.state
            history = saved.history
            clock = saved.clock
            provenWinnable = saved.provenWinnable
            phase = .playing
        } else {
            let mode = daily == nil ? Self.preferredMode : .draw1
            state = .deal(drawMode: mode, seed: .random(in: .min ... .max))
            phase = .preparing
            dealtCount = 0
            prepare(mode: mode)
        }
    }

    // MARK: - Derived

    var drawMode: Logic.DrawMode { state.drawMode }
    var isInteractive: Bool { phase == .playing && !showStuck }
    var canUndo: Bool { phase == .playing && !history.isEmpty }
    var canAutoComplete: Bool { phase == .playing && state.canAutoComplete }
    var variant: String { drawMode.rawValue }
    var bestScore: Int? { stats.stats(for: game, variant: variant).bestScore }
    var bestTime: TimeInterval? { stats.stats(for: game, variant: variant).bestTime }

    private static var preferredMode: Logic.DrawMode {
        Logic.DrawMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .draw1
    }

    /// Cards lifted together when grabbing `card`, or `nil` if it can't be picked up.
    func liftedCards(for card: Card) -> [Card]? {
        guard isInteractive, let (pile, index) = state.location(of: card), pile != .stock,
              let count = state.pickUpCount(pile: pile, index: index) else { return nil }
        return Array(state.cards(in: pile).suffix(count))
    }

    func legalMoves(for card: Card) -> [Logic.Move] {
        guard isInteractive, let (pile, index) = state.location(of: card) else { return [] }
        return state.moves(forCardAt: pile, index: index)
    }

    // MARK: - Actions

    func tapStock() {
        guard isInteractive else { return }
        guard state.canDraw else {
            Feedback.play(.invalid)
            return
        }
        perform(state.stock.isEmpty ? .recycle : .draw)
    }

    /// Sends a tapped card to its best destination, or shakes it if there is none.
    func tap(_ card: Card) {
        guard isInteractive, let (pile, index) = state.location(of: card) else { return }
        if pile == .stock { tapStock(); return }
        if let move = state.bestMove(forCardAt: pile, index: index) {
            perform(move)
        } else {
            reject(liftedCards(for: card) ?? [card])
        }
    }

    /// Drops the run headed by `card` on `target`. Returns whether the move happened.
    @discardableResult
    func drop(_ card: Card, on target: Logic.Pile) -> Bool {
        guard isInteractive, let (pile, index) = state.location(of: card),
              let count = state.pickUpCount(pile: pile, index: index) else { return false }
        return perform(Logic.Move(from: pile, to: target, count: count))
    }

    func reject<C: Sequence>(_ cards: C) where C.Element == Card {
        for card in cards { shakeCounts[card.id, default: 0] += 1 }
        Feedback.play(.invalid)
    }

    func shakeCount(_ id: Int) -> Int { shakeCounts[id] ?? 0 }

    @discardableResult
    func perform(_ move: Logic.Move) -> Bool {
        guard isInteractive else { return false }
        let previous = state
        guard let outcome = state.apply(move) else { return false }
        history.append(previous)
        if history.count > Self.maxUndo { history.removeFirst() }
        raisedIDs = Set(outcome.cards.map(\.id))
        hint = nil
        revision += 1
        clock.start()
        playFeedback(for: outcome)
        announce(outcome)
        afterMove()
        return true
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        raisedIDs = Self.movedCards(from: state, to: previous)
        state = previous
        hint = nil
        revision += 1
        showStuck = false
        stuckDismissed = false
        Feedback.play(.tap)
        persist()
    }

    func showHint() {
        guard isInteractive else { return }
        guard let move = state.hint() else {
            Feedback.play(.invalid)
            showStuck = true
            clock.pause()
            return
        }
        hint = move
        Feedback.play(.select)
        hintToken += 1
        let token = hintToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.hintToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.hint = nil }
        }
    }

    func dismissStuck() {
        showStuck = false
        stuckDismissed = true
        clock.start()
    }

    func autoComplete() {
        guard canAutoComplete else { return }
        phase = .autoCompleting
        hint = nil
        clock.start()
        Task { @MainActor [weak self] in
            while let self, self.phase == .autoCompleting {
                var next = self.state
                guard let outcome = next.autoCompleteStep() else { break }
                withAnimation(self.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.9)) {
                    self.state = next
                    self.raisedIDs = Set(outcome.cards.map(\.id))
                    self.revision += 1
                }
                if outcome.cards.first.map({ $0.rank % 4 == 0 }) == true { Haptics.tap() }
                try? await Task.sleep(for: .milliseconds(self.reduceMotion ? 40 : 85))
            }
            // A new game may have been started meanwhile.
            guard let self, self.phase == .autoCompleting else { return }
            if self.state.isWon { self.win() } else { self.phase = .playing }
        }
    }

    /// Deals a new game. On the daily, this restarts today's deal instead.
    func newGame(_ mode: Logic.DrawMode? = nil) {
        let mode = daily == nil ? mode ?? drawMode : .draw1
        if daily == nil { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
        if daily == nil && phase != .won && phase != .celebrating && state.moveCount > 0 {
            // An abandoned game with progress counts as a loss.
            stats.record(game, variant: variant, won: false, time: clock.elapsed())
        }
        store.remove(key: saveKey)
        history = []
        hint = nil
        showStuck = false
        stuckDismissed = false
        clock = GameClock()
        raisedIDs = []
        withAnimation(.easeInOut(duration: 0.3)) {
            state = .deal(drawMode: mode, seed: .random(in: .min ... .max))
            dealtCount = 0
            phase = .preparing
            revision += 1
        }
        prepare(mode: mode)
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
        if !active { persist() }
    }

    // MARK: - Dealing

    private func prepare(mode: Logic.DrawMode) {
        prepareTask?.cancel()
        let seed = daily.map { game.dailySeed($0) } ?? UInt64.random(in: .min ... .max)
        let deterministic = daily != nil
        prepareTask = Task { [weak self] in
            let deal = await Self.findDeal(mode: mode, seed: seed, deterministic: deterministic)
            guard !Task.isCancelled, let self else { return }
            self.state = deal.state
            self.provenWinnable = deal.provenWinnable
            self.revision += 1
            await self.animateDeal()
        }
    }

    /// Searches for a provably winnable deal off the main actor, giving up after a few seconds.
    /// A `deterministic` search (the daily deal) has no time limit, so every device finds the same
    /// deal; the attempt and node budgets still bound it.
    nonisolated private static func findDeal(mode: Logic.DrawMode, seed: UInt64, deterministic: Bool) async -> Logic.Deal {
        await Task.detached(priority: .userInitiated) {
            let deadline = ContinuousClock.now + .seconds(3)
            return Logic.winnableDeal(drawMode: mode, seed: seed, maxAttempts: 60, nodeBudget: 6_000) {
                !Task.isCancelled && (deterministic || ContinuousClock.now < deadline)
            }
        }.value
    }

    private func animateDeal() async {
        phase = .dealing
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { dealtCount = 28 }
        } else {
            for i in 1...28 {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { dealtCount = i }
                try? await Task.sleep(for: .milliseconds(32))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled else { return }
        dealtCount = 28
        phase = .playing
    }

    /// Deal order of a tableau card in the initial layout (row by row, left to right).
    static func dealIndex(column: Int, row: Int) -> Int {
        row * 7 - row * (row - 1) / 2 + (column - row)
    }

    #if DEBUG
    /// `-solitaireScenario autocomplete` (or `autowin`, which also runs it) starts from a solved position (every card face up),
    /// for screenshots and UI tests.
    private static func debugScenario() -> Logic.State? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-solitaireScenario"), i + 1 < args.count,
              ["autocomplete", "autowin"].contains(args[i + 1]) else { return nil }
        for seed in UInt64(1)...200 {
            var state = Logic.State.deal(drawMode: .draw1, seed: seed)
            let result = Logic.Solver.solve(state, nodeBudget: 4_000)
            guard result.solved else { continue }
            for move in result.moves {
                state.apply(move)
                if state.canAutoComplete && state.foundationCount >= 20 { return state }
            }
        }
        return nil
    }
    #endif

    // MARK: - Private

    /// Cards whose pile differs between two states.
    private static func movedCards(from a: Logic.State, to b: Logic.State) -> Set<Int> {
        Set(Card.deck.filter { a.location(of: $0)?.pile != b.location(of: $0)?.pile }.map(\.id))
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
        clock.pause()
        finalTime = clock.elapsed()
        timeBonus = Logic.Scoring.timeBonus(seconds: finalTime)
        finalScore = state.score + timeBonus
        let previousBest = bestScore
        isNewBest = previousBest.map { finalScore > $0 } ?? true
        if let daily {
            DailyStore.shared.record(game, on: daily, won: true, time: finalTime)
        } else {
            stats.record(game, variant: variant, won: true, score: finalScore, time: finalTime)
        }
        store.remove(key: saveKey)
        hint = nil
        Feedback.play(.win)
        celebrationStart = .now
        withAnimation(.easeOut(duration: 0.2)) {
            phase = reduceMotion ? .won : .celebrating
        }
    }

    private func playFeedback(for outcome: Logic.Outcome) {
        switch (outcome.move.from, outcome.move.to) {
        case (.stock, _): Feedback.play(.flip)
        case (_, .stock): Feedback.play(.move)
        case (_, .foundation): Feedback.play(.pop)
        default: Feedback.play(outcome.flipped != nil ? .flip : .place)
        }
    }

    private func announce(_ outcome: Logic.Outcome) {
        var parts: [String] = []
        if outcome.move == .draw, let top = state.waste.last { parts.append("Drew \(top.name)") }
        if outcome.move == .recycle { parts.append("Stock turned over") }
        if let flipped = outcome.flipped { parts.append("Revealed \(flipped.name)") }
        guard !parts.isEmpty else { return }
        AccessibilityNotification.Announcement(parts.joined(separator: ". ")).post()
    }

    private func persist() {
        guard phase != .won, phase != .celebrating else { return }
        guard state.moveCount > 0 else {
            // Undone back to the deal: nothing worth resuming.
            store.remove(key: saveKey)
            return
        }
        store.save(Saved(state: state, history: history, clock: clock, provenWinnable: provenWinnable), key: saveKey)
    }
}
