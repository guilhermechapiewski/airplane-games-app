import SwiftUI
import GameLogic

@MainActor @Observable
final class WordSearchModel {
    typealias Logic = WordSearch

    private struct Saved: Codable {
        var state: Logic.State
        var clock: GameClock
        var categoryID: String?
    }

    private(set) var state: Logic.State?
    private(set) var difficulty: Difficulty
    /// Chosen theme; `nil` = a random theme each game.
    private(set) var categoryID: String?
    private(set) var clock = GameClock()
    private(set) var isGenerating = false
    private(set) var showWin = false
    /// Placement index whose first letter is flashing, with a token to restart the animation.
    private(set) var hint: (index: Int, token: Int)?
    /// The cell where a tap-to-select (VoiceOver-friendly) selection started.
    var pendingStart: GridPoint?
    private(set) var lastFoundIndex: Int?
    private(set) var isNewBest = false

    private let store: GameStore
    private let stats: StatsStore
    private var hintToken = 0
    private var generation = 0
    private var isActive = false
    let game = GameID.wordSearch
    static let difficulties: [Difficulty] = [.easy, .medium, .hard]
    private static let difficultyKey = "wordSearch.difficulty"
    private static let categoryKey = "wordSearch.category"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let defaults = UserDefaults.standard
        difficulty = Difficulty(rawValue: defaults.string(forKey: Self.difficultyKey) ?? "") ?? .easy
        categoryID = defaults.string(forKey: Self.categoryKey).flatMap { WordCategory.named($0)?.id }
        if let saved = store.load(Saved.self, key: GameID.wordSearch.saveKey), !saved.state.isComplete {
            state = saved.state
            clock = saved.clock
            difficulty = saved.state.difficulty
            categoryID = saved.categoryID
        } else {
            startGeneration()
        }
    }

    // MARK: Derived

    var foundCount: Int { state?.found.count ?? 0 }
    var totalCount: Int { state?.puzzle.placements.count ?? 0 }
    var bestTime: TimeInterval? { stats.stats(for: game, variant: difficulty.rawValue).bestTime }

    /// Order in which a placement was found (for its highlight color), or `nil`.
    func foundOrder(_ index: Int) -> Int? { state?.found.firstIndex(of: index) }

    // MARK: Selection

    func select(from a: GridPoint, to b: GridPoint) {
        guard var s = state, !s.isComplete else { return }
        pendingStart = nil
        guard a != b else { return }
        let result = s.select(from: a, to: b)
        state = s
        switch result {
        case .found(let index):
            lastFoundIndex = index
            if hint?.index == index { hint = nil }
            if s.isComplete {
                finish()
            } else {
                Feedback.play(.merge)
            }
            AccessibilityNotification.Announcement("Found \(s.puzzle.placements[index].word.uppercased())").post()
        case .alreadyFound:
            Haptics.tap()
        case .miss:
            Feedback.play(.invalid)
        }
        persist()
    }

    /// Tap-to-select: first tap marks the start, second tap the end.
    func tapCell(_ p: GridPoint) {
        guard let s = state, !s.isComplete else { return }
        if let start = pendingStart {
            if start == p {
                pendingStart = nil
                Haptics.tap()
            } else if WordSearch.line(from: start, to: p) == nil {
                pendingStart = p
                Feedback.play(.select)
            } else {
                select(from: start, to: p)
            }
        } else {
            pendingStart = p
            Feedback.play(.select)
            AccessibilityNotification.Announcement("Start \(s.puzzle.letter(at: p).uppercased()). Now choose the last letter.").post()
        }
    }

    func useHint() {
        guard var s = state, !s.isComplete, let index = s.useHint() else { return }
        state = s
        hintToken += 1
        hint = (index, hintToken)
        Feedback.play(.pop)
        let word = s.puzzle.placements[index].word
        let start = s.puzzle.placements[index].start
        AccessibilityNotification.Announcement("\(word.uppercased()) starts at row \(start.row + 1), column \(start.col + 1)").post()
        persist()
        let token = hintToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.hint?.token == token else { return }
            withAnimation { self.hint = nil }
        }
    }

    private func finish() {
        clock.pause()
        let time = clock.elapsed()
        let previousBest = bestTime
        stats.record(game, variant: difficulty.rawValue, won: true, time: time)
        isNewBest = previousBest.map { time < $0 } ?? true
        store.remove(key: game.saveKey)
        Feedback.play(.win)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, self.state?.isComplete == true else { return }
            withAnimation { self.showWin = true }
        }
    }

    // MARK: New games

    func newGame(difficulty: Difficulty? = nil) {
        if let difficulty {
            self.difficulty = difficulty
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
        abandonIfNeeded()
        store.remove(key: game.saveKey)
        startGeneration()
    }

    func chooseCategory(_ id: String?) {
        categoryID = id
        UserDefaults.standard.set(id, forKey: Self.categoryKey)
        newGame()
    }

    private func abandonIfNeeded() {
        if let s = state, !s.isComplete, !s.found.isEmpty {
            stats.record(game, variant: s.difficulty.rawValue, won: false)
        }
    }

    private func startGeneration() {
        generation += 1
        let token = generation
        let difficulty = self.difficulty
        let categoryID = self.categoryID
        isGenerating = true
        showWin = false
        hint = nil
        pendingStart = nil
        lastFoundIndex = nil
        clock = GameClock()
        Task { @MainActor [weak self] in
            let state = await Self.generate(difficulty: difficulty, categoryID: categoryID)
            guard let self, self.generation == token else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.state = state
                self.isGenerating = false
            }
            if self.isActive { self.clock.start() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoState") {
                for p in state.puzzle.placements.prefix(3) { self.select(from: p.start, to: p.end) }
            }
            #endif
        }
    }

    nonisolated private static func generate(difficulty: Difficulty, categoryID: String?) async -> Logic.State {
        await Task.detached(priority: .userInitiated) {
            var rng = SeededRandom()
            let category = categoryID.flatMap(WordCategory.named) ?? WordCategory.all.randomElement(using: &rng)!
            let puzzle = WordSearch.generate(category: category, difficulty: difficulty, using: &rng)
            return Logic.State(puzzle: puzzle, difficulty: difficulty)
        }.value
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active, let s = state, !s.isComplete, !isGenerating { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    private func persist() {
        guard let s = state else { return }
        if s.isComplete {
            store.remove(key: game.saveKey)
        } else if !s.found.isEmpty || s.hintsUsed > 0 || clock.elapsed() >= 5 {
            store.save(Saved(state: s, clock: clock, categoryID: categoryID), key: game.saveKey)
        }
    }
}
