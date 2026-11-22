import SwiftUI
import GameLogic

@MainActor @Observable
final class TwentyFortyEightModel {
    typealias Logic = TwentyFortyEight

    private struct Saved: Codable {
        var state: Logic.State
        var history: [Logic.State]
        var keepPlaying: Bool
        var clock: GameClock
    }

    private(set) var state: Logic.State
    /// Tiles absorbed by the latest merge, still visible while they slide.
    private(set) var ghosts: [Logic.Tile] = []
    /// Ids of tiles that should play a "pop" animation; bumped each move.
    private(set) var mergedIDs: Set<Int> = []
    private(set) var moveCount = 0
    private(set) var history: [Logic.State] = []
    private(set) var keepPlaying = false
    private(set) var clock = GameClock()
    var showWin = false
    private(set) var isOver = false

    private let store: GameStore
    private let stats: StatsStore
    private static let maxUndo = 20
    let game = GameID.twentyFortyEight

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        if let saved = store.load(Saved.self, key: GameID.twentyFortyEight.saveKey) {
            state = saved.state
            history = saved.history
            keepPlaying = saved.keepPlaying
            clock = saved.clock
            isOver = !saved.state.canMove
        } else {
            state = .newGame()
        }
    }

    var best: Int { max(stats.stats(for: game).bestScore ?? 0, state.score) }
    var canUndo: Bool { !history.isEmpty && !isOver }

    func move(_ direction: Direction) {
        guard !isOver, !showWin else { return }
        let previous = state
        guard let outcome = state.move(direction) else {
            Haptics.tap()
            return
        }
        history.append(previous)
        if history.count > Self.maxUndo { history.removeFirst() }
        ghosts = outcome.consumed
        mergedIDs = outcome.merged
        moveCount += 1
        clock.start()

        if outcome.scoreGained > 0 {
            Feedback.play(outcome.merged.count > 1 || outcome.scoreGained >= 128 ? .clear : .merge)
            stats.submitScore(game, score: state.score)
        } else {
            Feedback.play(.move)
        }

        if state.hasWon && !keepPlaying {
            showWin = true
            clock.pause()
            Feedback.play(.win)
        } else if !state.canMove {
            finish()
        }
        persist()

        // Drop ghosts once the slide animation has finished.
        let token = moveCount
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, self.moveCount == token else { return }
            self.ghosts = []
        }
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        state = previous
        ghosts = []
        mergedIDs = []
        moveCount += 1
        Feedback.play(.flip)
        persist()
    }

    func continueAfterWin() {
        keepPlaying = true
        showWin = false
        clock.start()
        persist()
    }

    func newGame() {
        if state.score > 0 && !isOver {
            // Count an abandoned game that had progress.
            stats.record(game, won: state.hasWon, score: state.score, time: clock.elapsed())
        }
        state = .newGame()
        history = []
        ghosts = []
        mergedIDs = []
        keepPlaying = false
        showWin = false
        isOver = false
        clock = GameClock()
        moveCount += 1
        store.remove(key: game.saveKey)
    }

    func setActive(_ active: Bool) {
        if active, !isOver, !showWin, state.score > 0 { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    private func finish() {
        isOver = true
        clock.pause()
        stats.record(game, won: state.hasWon, score: state.score, time: clock.elapsed())
        Feedback.play(state.hasWon ? .win : .lose)
    }

    private func persist() {
        if isOver {
            store.remove(key: game.saveKey)
        } else if state.score > 0 || !history.isEmpty {
            store.save(Saved(state: state, history: history, keepPlaying: keepPlaying, clock: clock), key: game.saveKey)
        }
    }
}
