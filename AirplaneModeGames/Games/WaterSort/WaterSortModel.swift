import SwiftUI
import GameLogic

@MainActor @Observable
final class WaterSortModel {
    typealias Logic = WaterSort

    private struct Saved: Codable {
        var level: Int
        var state: Logic.State
        var clock: GameClock
    }

    /// The level to play next; gameplay progress, kept apart from the statistics.
    private struct Progress: Codable {
        var level: Int
    }

    /// A pour on screen: the source tube flies over the target, tilts and the liquid transfers.
    /// Purely visual: the state already holds the result, and the next move can start right away.
    struct PourAnimation: Identifiable {
        let id: Int
        let pour: Logic.Pour
        /// The source and target layers before the pour.
        let sourceBefore: [Int]
        let targetBefore: [Int]
        let start: Date

        static let duration: TimeInterval = 0.62

        func touches(_ tube: Int) -> Bool { pour.from == tube || pour.to == tube }
    }

    private(set) var state: Logic.State
    /// The level being played.
    private(set) var level: Int
    private(set) var clock = GameClock()

    private(set) var selected: Int?
    private(set) var pours: [PourAnimation] = []
    private var pourCounter = 0
    /// Per tube, the token of its latest shake / completion sparkle (a change triggers it).
    private(set) var shakeTokens: [Int: Int] = [:]
    private(set) var sparkleTokens: [Int: Int] = [:]
    private var effectCounter = 0
    /// Bumped when a new puzzle is laid out, so tubes can animate in.
    private(set) var puzzleToken = 0

    var showWin = false
    private(set) var showStuck = false
    /// Out of useful pours, with the extra tube still to use.
    private(set) var needsExtraTube = false
    /// The latest hint; a suggested pour stays highlighted until the board changes.
    private(set) var hint: Logic.Hint?
    /// A hint is being worked out (big puzzles can take a moment).
    private(set) var isThinking = false
    private var planner = Logic.HintPlanner()
    private var hintToken = 0
    /// The level just finished (shown on the result card).
    private(set) var solvedLevel = 0
    private(set) var solvedMoves = 0

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.waterSort
    private static let progressKey = "waterSort.progress"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let progress = store.load(Progress.self, key: Self.progressKey)?.level ?? 1
        if let saved = store.load(Saved.self, key: GameID.waterSort.saveKey), !saved.state.isSolved {
            state = saved.state
            level = saved.level
            clock = saved.clock
        } else {
            level = progress
            state = Logic.State(puzzle: Logic.level(progress))
        }
        #if DEBUG
        if let scenario = Self.debugScenario() { state = scenario }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-waterSortLevel"),
           i + 1 < ProcessInfo.processInfo.arguments.count, let n = Int(ProcessInfo.processInfo.arguments[i + 1]) {
            level = n
            state = Logic.State(puzzle: Logic.level(n))
        }
        #endif
        updateStuck(announce: false)
    }

    // MARK: Derived

    var tubeCount: Int { state.tubes.count }
    var moves: Int { state.moveCount }
    var canUndo: Bool { state.canUndo && !state.isSolved }
    var canAddTube: Bool { !state.extraTubeUsed && !state.isSolved }
    /// Levels solved so far.
    var levelsSolved: Int { stats.stats(for: game).won }

    // MARK: Actions

    /// Picks a tube up, puts it back, or pours the picked-up tube into it.
    func tap(_ tube: Int, animated: Bool) {
        guard !state.isSolved, state.tubes.indices.contains(tube) else { return }
        if let from = selected {
            if from == tube {
                selected = nil
                Feedback.play(.tap)
            } else if state.canPour(from: from, to: tube) {
                pour(from: from, to: tube, animated: animated)
            } else {
                // Can't go there: the target shakes and the tube is put back.
                shake(tube)
                selected = nil
                Feedback.play(.invalid)
            }
            return
        }
        guard state.canPick(tube) else {
            if !state.tubes[tube].isEmpty { shake(tube) }
            Feedback.play(.tap)
            return
        }
        finishAnimations(touching: tube)
        selected = tube
        Feedback.play(.select)
    }

    /// Pours `from` into `to` directly (VoiceOver's "Pour into tube N").
    func pour(from: Int, to: Int, animated: Bool) {
        guard !state.isSolved else { return }
        let before = state.tubes
        guard state.canPour(from: from, to: to) else { return }
        beginIfNeeded()
        finishAnimations(touching: from)
        finishAnimations(touching: to)
        guard let pour = state.apply(from: from, to: to) else { return }
        clearHint()
        selected = nil
        let landing: Duration
        if animated {
            pourCounter += 1
            pours.append(PourAnimation(id: pourCounter, pour: pour, sourceBefore: before[from],
                                       targetBefore: before[to], start: .now))
            let id = pourCounter
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(PourAnimation.duration))
                self?.pours.removeAll { $0.id == id }
            }
            landing = .milliseconds(380)
        } else {
            landing = .zero
        }
        Feedback.play(.move)
        if state.isComplete(to) {
            effectCounter += 1
            let token = effectCounter
            Task { @MainActor [weak self] in
                if landing > .zero { try? await Task.sleep(for: landing) }
                guard let self, self.state.isComplete(to) else { return }
                self.sparkleTokens[to] = token
                if !self.state.isSolved { Feedback.play(.pop) }
            }
        }
        if state.isSolved {
            finishWin(after: animated ? .milliseconds(650) : .milliseconds(150))
        } else {
            updateStuck(announce: true)
        }
        persist()
    }

    func undo() {
        guard canUndo else { return }
        pours = []
        state.undo()
        clearHint()
        selected = nil
        Feedback.play(.flip)
        updateStuck(announce: false)
        clock.start()
        persist()
    }

    func addExtraTube() {
        guard canAddTube else { return }
        beginIfNeeded()
        state.addExtraTube()
        clearHint()
        selected = nil
        Feedback.play(.place)
        updateStuck(announce: false)
        persist()
    }

    /// Starts the current puzzle over. An attempt with progress counts as a played level.
    func restart() {
        guard !state.isSolved || showWin else { return }
        if !showWin && hasProgress {
            stats.record(game, won: false)
        }
        state.restart()
        resetPlay()
        store.remove(key: game.saveKey)
    }

    /// Moves on to the next level after a win.
    func nextLevel() {
        level = store.load(Progress.self, key: Self.progressKey)?.level ?? level + 1
        state = Logic.State(puzzle: Logic.level(level))
        resetPlay()
        store.remove(key: game.saveKey)
    }

    // MARK: Hints

    /// Works out the next step off the main actor. A pour is highlighted until the board changes;
    /// when the puzzle can't be sorted from here, the hint says how to recover. Hints are free,
    /// unlimited.
    func showHint() {
        guard !state.isSolved, !isThinking else { return }
        hintToken += 1
        let token = hintToken
        let position = state
        let current = planner
        isThinking = true
        Task { @MainActor [weak self] in
            let (hint, updated) = await Task.detached(priority: .userInitiated) {
                var planner = current
                let hint = planner.hint(for: position)
                return (hint, planner)
            }.value
            guard let self, self.hintToken == token else { return }
            self.isThinking = false
            self.planner = updated
            guard let hint else { return }
            self.selected = nil
            withAnimation(.easeOut(duration: 0.2)) { self.hint = hint }
            Feedback.play(.select)
            AccessibilityNotification.Announcement(Self.describe(hint)).post()
        }
    }

    /// The hint in words.
    static func describe(_ hint: Logic.Hint) -> String {
        switch hint {
        case let .pour(p): "Pour tube \(p.from + 1) into tube \(p.to + 1)."
        case .addExtraTube: "This can't be sorted with these tubes. Add the extra tube."
        case let .undo(steps): steps == 1
            ? "This can't be sorted from here. Undo your last pour."
            : "This can't be sorted from here. Undo your last \(steps) pours."
        case .restart: "This can't be sorted from here. Restart the level."
        }
    }

    /// Carries out a recovery hint (Add Extra Tube, Undo or Restart).
    func applyHint() {
        guard let hint else { return }
        switch hint {
        case .pour: clearHint()
        case .addExtraTube: addExtraTube()
        case let .undo(steps): for _ in 0..<steps { undo() }
        case .restart: restart()
        }
    }

    func dismissHint() {
        withAnimation(.easeOut(duration: 0.2)) { clearHint() }
    }

    private func clearHint() {
        hintToken += 1
        hint = nil
        isThinking = false
    }

    func setActive(_ active: Bool) {
        if active, hasProgress, !showWin, !showStuck { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Helpers

    private var hasProgress: Bool { state.canUndo || state.extraTubeUsed }

    private func resetPlay() {
        clearHint()
        clock = GameClock()
        selected = nil
        pours = []
        shakeTokens = [:]
        sparkleTokens = [:]
        showWin = false
        showStuck = false
        needsExtraTube = false
        puzzleToken += 1
        updateStuck(announce: false)
    }

    private func beginIfNeeded() {
        clock.start()
    }

    private func finishAnimations(touching tube: Int) {
        pours.removeAll { $0.touches(tube) }
    }

    private func shake(_ tube: Int) {
        effectCounter += 1
        shakeTokens[tube] = effectCounter
    }

    private func updateStuck(announce: Bool) {
        let stuck = state.isStuck
        needsExtraTube = stuck && !state.extraTubeUsed
        let wasStuck = showStuck
        showStuck = stuck && state.extraTubeUsed
        if showStuck { clock.pause() }
        if announce && stuck && !wasStuck { Haptics.warning() }
    }

    private func finishWin(after delay: Duration) {
        clock.pause()
        let time = clock.elapsed()
        solvedMoves = state.moveCount
        solvedLevel = level
        stats.record(game, won: true, time: time)
        store.save(Progress(level: level + 1), key: Self.progressKey)
        store.remove(key: game.saveKey)
        selected = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.state.isSolved else { return }
            Feedback.play(.win)
            withAnimation(.easeOut(duration: 0.25)) { self.showWin = true }
        }
    }

    private func persist() {
        if state.isSolved || !hasProgress {
            store.remove(key: game.saveKey)
        } else {
            store.save(Saved(level: level, state: state, clock: clock), key: game.saveKey)
        }
    }

    #if DEBUG
    /// `-waterSortLevel <n>` opens level n (screenshots).
    /// `-waterSortScenario nearlySolved` starts one pour from the end (pour tube 3 into tube 2),
    /// for UI tests and screenshots.
    private static func debugScenario() -> Logic.State? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-waterSortScenario"), i + 1 < args.count,
              args[i + 1] == "nearlySolved" else { return nil }
        return Logic.State(tubes: [[0, 0, 0, 0], [5, 5, 5], [5], [], [7, 7, 7, 7]])
    }
    #endif
}
