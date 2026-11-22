import SwiftUI
import GameLogic

@MainActor @Observable
final class MinesweeperModel {
    typealias Logic = Minesweeper

    enum Mode: String, Codable {
        case reveal, flag

        var toggled: Mode { self == .reveal ? .flag : .reveal }
    }

    private struct Saved: Codable {
        var level: Logic.Level
        var state: Logic.State
        var clock: GameClock
        var mode: Mode
    }

    private(set) var level: Logic.Level
    private(set) var state: Logic.State
    private(set) var clock = GameClock()
    var mode: Mode = .reveal {
        didSet { if oldValue != mode { persist() } }
    }

    /// Per-cell animation delays for the latest reveal ripple / explosion.
    private(set) var revealDelays: [GridPoint: Double] = [:]
    private(set) var explosionDelays: [GridPoint: Double] = [:]
    /// Bumped for every new board so views can reset zoom.
    private(set) var boardID = 0
    /// Whether the end-of-game card is visible (the player may hide it to inspect the board).
    var showResult = false
    private(set) var isNewBest = false
    private(set) var finalTime: TimeInterval = 0

    private let store: GameStore
    private let stats: StatsStore
    private var pendingResult: Task<Void, Never>?
    let game = GameID.minesweeper
    private static let levelKey = "minesweeper.level"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        if let saved = store.load(Saved.self, key: GameID.minesweeper.saveKey), !saved.state.status.isOver {
            level = saved.level
            state = saved.state
            clock = saved.clock
            mode = saved.mode
        } else {
            let level = store.load(Logic.Level.self, key: Self.levelKey) ?? .beginner
            self.level = level
            state = Logic.State(level: level)
        }
        #if DEBUG
        applyDemoArguments()
        #endif
    }

    #if DEBUG
    /// `-minesweeperDemo <level> <playing|lost|won>` sets up a board for screenshots.
    private func applyDemoArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-minesweeperDemo"), i + 2 < args.count,
              let demoLevel = Logic.Level(rawValue: args[i + 1]) else { return }
        level = demoLevel
        state = Logic.State(level: demoLevel, seed: 7)
        let center = GridPoint(row: demoLevel.rows / 2, col: demoLevel.cols / 2)
        _ = state.reveal(center)
        // Flag a few mines that border the opened area.
        let border = state.minePoints.filter { m in state.neighbors(of: m).contains { state[$0].isRevealed } }
        for m in border.prefix(4) { state.toggleFlag(m) }
        clock = GameClock()
        switch args[i + 2] {
        case "lost":
            state.toggleFlag(state.allPoints.first { state[$0].mark == .hidden && !state[$0].isMine }!)
            apply(state.reveal(state.allPoints.first { state[$0].mark == .hidden && state[$0].isMine }!))
        case "won":
            while state.status == .playing {
                _ = state.reveal(state.allPoints.first { state[$0].mark == .hidden && !state[$0].isMine }!)
            }
            win()
        default:
            break
        }
    }
    #endif

    // MARK: Derived

    var status: Logic.Status { state.status }
    var isOver: Bool { state.status.isOver }
    var hasProgress: Bool { state.status == .playing && state.revealedCount > 0 }
    var percentCleared: Int {
        Int((Double(state.revealedCount) / Double(max(1, state.safeCellCount)) * 100).rounded(.down))
    }
    var bestTime: TimeInterval? { stats.stats(for: game, variant: level.rawValue).bestTime }

    static var statsVariants: [StatsVariant] {
        Logic.Level.allCases.map { StatsVariant(key: $0.rawValue, title: $0.title, showsTime: true) }
    }

    // MARK: Actions

    /// A tap: performs the current mode's action (or chords a satisfied number).
    func tap(_ p: GridPoint) {
        guard !isOver, state.contains(p) else { return }
        if state[p].isRevealed {
            chord(p)
        } else if mode == .flag {
            toggleFlag(p)
        } else {
            reveal(p)
        }
    }

    /// A long press: the opposite of the current mode.
    func longPress(_ p: GridPoint) {
        guard !isOver, state.contains(p) else { return }
        if state[p].isRevealed {
            chord(p)
        } else if mode == .flag {
            reveal(p)
        } else {
            toggleFlag(p)
        }
    }

    func reveal(_ p: GridPoint) {
        guard !isOver, state.contains(p) else { return }
        guard state[p].mark == .hidden else {
            if state[p].isFlagged { Feedback.play(.invalid) }
            return
        }
        apply(state.reveal(p))
    }

    func chord(_ p: GridPoint) {
        guard state.canChord(at: p) else { return }
        apply(state.chord(p))
    }

    func toggleFlag(_ p: GridPoint) {
        guard state.toggleFlag(p) else { return }
        revealDelays = [:]
        if state[p].isFlagged { Feedback.play(.place) } else { Feedback.play(.flip) }
        persist()
    }

    func newGame(level newLevel: Logic.Level? = nil) {
        if hasProgress {
            // An abandoned game with progress counts as played.
            stats.record(game, variant: level.rawValue, won: false, time: clock.elapsed())
        }
        pendingResult?.cancel()
        if let newLevel {
            level = newLevel
            store.save(newLevel, key: Self.levelKey)
        }
        state = Logic.State(level: level)
        clock = GameClock()
        revealDelays = [:]
        explosionDelays = [:]
        showResult = false
        isNewBest = false
        mode = .reveal
        boardID += 1
        store.remove(key: game.saveKey)
    }

    func setActive(_ active: Bool) {
        if active, state.status == .playing { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Internals

    private func apply(_ outcome: Logic.Outcome) {
        guard !outcome.isEmpty else { return }
        clock.start()
        revealDelays = Self.rippleDelays(outcome.revealed)

        switch state.status {
        case .lost:
            lose(at: outcome.exploded ?? outcome.revealed.last ?? GridPoint(row: 0, col: 0))
        case .won:
            win()
        default:
            Feedback.play(outcome.revealed.count > 1 ? .pop : .tap)
        }
        persist()
    }

    private static func rippleDelays(_ order: [GridPoint]) -> [GridPoint: Double] {
        guard order.count > 1 else { return [:] }
        let step = min(0.012, 0.3 / Double(order.count))
        var delays: [GridPoint: Double] = [:]
        for (i, p) in order.enumerated() { delays[p] = Double(i) * step }
        return delays
    }

    private func lose(at boom: GridPoint) {
        clock.pause()
        finalTime = clock.elapsed()
        Feedback.play(.lose)
        Haptics.thud()
        // Mines go off in a wave spreading from the one that was hit.
        let mines = state.minePoints.filter { $0 != boom && !state[$0].isFlagged }
        let far = mines.map { distance($0, boom) }.max() ?? 1
        explosionDelays = Dictionary(uniqueKeysWithValues: mines.map { ($0, 0.15 + 0.85 * distance($0, boom) / max(far, 1)) })
        stats.record(game, variant: level.rawValue, won: false, time: finalTime)
        presentResult(after: mines.isEmpty ? 0.5 : 1.4)
    }

    private func win() {
        clock.pause()
        finalTime = clock.elapsed()
        let previousBest = bestTime
        isNewBest = previousBest.map { finalTime < $0 } ?? true
        stats.record(game, variant: level.rawValue, won: true, time: finalTime)
        Feedback.play(.win)
        presentResult(after: 0.6)
    }

    private func presentResult(after seconds: Double) {
        pendingResult?.cancel()
        let id = boardID
        pendingResult = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.boardID == id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.showResult = true }
        }
    }

    private func distance(_ a: GridPoint, _ b: GridPoint) -> Double {
        let dr = Double(a.row - b.row), dc = Double(a.col - b.col)
        return (dr * dr + dc * dc).squareRoot()
    }

    private func persist() {
        if state.status == .playing {
            store.save(Saved(level: level, state: state, clock: clock, mode: mode), key: game.saveKey)
        } else {
            store.remove(key: game.saveKey)
        }
    }
}
