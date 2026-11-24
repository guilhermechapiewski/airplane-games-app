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

    /// The level to play next (levels mode); gameplay progress, kept apart from the statistics.
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
    /// The level being played (levels mode).
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
    /// The level just finished (shown on the result card).
    private(set) var solvedLevel = 0
    private(set) var solvedMoves = 0

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.waterSort
    private static let progressKey = "waterSort.progress"

    /// Today, when this is the daily puzzle (fixed by the date, saved separately, no level change).
    let daily: Daily.Day?
    private var saveKey: String { daily.map { game.dailySaveKey($0) } ?? game.saveKey }

    init(daily: Daily.Day? = nil, store: GameStore = .shared, stats: StatsStore = .shared) {
        self.daily = daily
        self.store = store
        self.stats = stats
        let progress = store.load(Progress.self, key: Self.progressKey)?.level ?? 1
        let key = daily.map { GameID.waterSort.dailySaveKey($0) } ?? GameID.waterSort.saveKey
        if let saved = store.load(Saved.self, key: key), !saved.state.isSolved {
            state = saved.state
            level = saved.level
            clock = saved.clock
        } else if let daily {
            level = progress
            state = Logic.State(puzzle: Logic.daily(seed: GameID.waterSort.dailySeed(daily)))
        } else {
            level = progress
            state = Logic.State(puzzle: Logic.level(progress))
        }
        #if DEBUG
        if let scenario = Self.debugScenario() { state = scenario }
        if daily == nil, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-waterSortLevel"),
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
    var isDaily: Bool { daily != nil }
    /// Levels solved so far (levels mode).
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
        selected = nil
        Feedback.play(.place)
        updateStuck(announce: false)
        persist()
    }

    /// Starts the current puzzle over. In levels mode an attempt with progress counts as a played level.
    func restart() {
        guard !state.isSolved || showWin else { return }
        if daily == nil && !showWin && hasProgress {
            stats.record(game, won: false)
        }
        state.restart()
        resetPlay()
        store.remove(key: saveKey)
    }

    /// Moves on to the next level after a win.
    func nextLevel() {
        guard daily == nil else { return }
        level = store.load(Progress.self, key: Self.progressKey)?.level ?? level + 1
        state = Logic.State(puzzle: Logic.level(level))
        resetPlay()
        store.remove(key: saveKey)
    }

    func setActive(_ active: Bool) {
        if active, hasProgress, !showWin, !showStuck { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Helpers

    private var hasProgress: Bool { state.canUndo || state.extraTubeUsed }

    private func resetPlay() {
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
        if let daily {
            DailyStore.shared.record(game, on: daily, won: true, time: time)
        } else {
            solvedLevel = level
            stats.record(game, won: true, time: time)
            store.save(Progress(level: level + 1), key: Self.progressKey)
        }
        store.remove(key: saveKey)
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
            store.remove(key: saveKey)
        } else {
            store.save(Saved(level: level, state: state, clock: clock), key: saveKey)
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
