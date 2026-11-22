import SwiftUI
import GameLogic

@MainActor @Observable
final class SudokuModel {
    private struct Saved: Codable {
        var game: Sudoku.Game
        var clock: GameClock
        var selected: Int?
        var notesMode: Bool
        var isPaused: Bool
    }

    /// `nil` only while the very first puzzle is being generated.
    private(set) var game: Sudoku.Game?
    private(set) var difficulty: Difficulty
    private(set) var selected: Int?
    private(set) var notesMode = false
    private(set) var clock = GameClock()
    private(set) var isGenerating = false
    /// Becomes true when generation takes long enough to deserve a spinner.
    private(set) var showSpinner = false
    private(set) var isPaused = false
    private(set) var isSolved = false
    private(set) var showWin = false
    private(set) var isNewBest = false
    /// The latest hint, shown briefly as a banner.
    private(set) var hintBanner: Sudoku.Hint?

    /// Per-cell animation counters: bump to replay a "pop" or a completion "wave".
    private(set) var popCount = [Int](repeating: 0, count: Sudoku.cellCount)
    private(set) var waveCount = [Int](repeating: 0, count: Sudoku.cellCount)
    private(set) var waveDelay = [Double](repeating: 0, count: Sudoku.cellCount)

    private var isActive = false
    private var generation = 0
    private var bannerToken = 0
    private let store: GameStore
    private let stats: StatsStore
    let gameID = GameID.sudoku
    private static let difficultyKey = "sudoku.lastDifficulty"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let last = UserDefaults.standard.string(forKey: Self.difficultyKey).flatMap(Difficulty.init(rawValue:))
        difficulty = last ?? .easy
        if let saved = store.load(Saved.self, key: GameID.sudoku.saveKey), !saved.game.isSolved {
            game = saved.game
            difficulty = saved.game.difficulty
            clock = saved.clock
            selected = saved.selected
            notesMode = saved.notesMode
            isPaused = saved.isPaused
        } else {
            startGeneration(difficulty)
        }
    }

    // MARK: - Derived state

    var bestTime: TimeInterval? { stats.stats(for: gameID, variant: difficulty.rawValue).bestTime }
    var canInteract: Bool { game != nil && !isGenerating && !isPaused && !isSolved }
    var canUndo: Bool { canInteract && (game?.canUndo ?? false) }

    /// The digit to highlight across the board (the selected cell's digit).
    var highlightedDigit: Int? {
        guard let game, let selected, game.values[selected] != 0 else { return nil }
        return game.values[selected]
    }

    var canErase: Bool {
        guard canInteract, let game, let selected, !game.isGiven(selected) else { return false }
        return game.values[selected] != 0 || game.notes[selected] != 0
    }

    func remaining(_ digit: Int) -> Int { game?.remaining(digit) ?? 9 }

    // MARK: - Actions

    func select(_ cell: Int) {
        guard canInteract, (0..<Sudoku.cellCount).contains(cell), selected != cell else { return }
        selected = cell
        Haptics.select()
        persist()
    }

    /// Moves the selection like arrow keys, wrapping around the edges.
    func moveSelection(_ direction: Direction) {
        guard canInteract else { return }
        guard let current = selected else { select(40); return }
        let r = (Sudoku.row(of: current) + direction.offset.row + 9) % 9
        let c = (Sudoku.column(of: current) + direction.offset.col + 9) % 9
        select(Sudoku.index(row: r, column: c))
    }

    func toggleNotesMode() {
        guard canInteract else { return }
        notesMode.toggle()
        Feedback.play(.flip)
        persist()
    }

    /// A number-pad press: writes the digit or toggles the note in the selected cell.
    func input(_ digit: Int) {
        guard canInteract, var game, let cell = selected else { return }
        if game.isGiven(cell) {
            Haptics.tap()
            return
        }
        if notesMode && game.values[cell] == 0 {
            guard game.toggleNote(digit, at: cell) else { return }
            self.game = game
            Feedback.play(.tap)
            persist()
        } else {
            place(digit, at: cell)
        }
    }

    /// VoiceOver adjustable action: steps a cell's digit up or down (0 = empty).
    func adjust(_ cell: Int, up: Bool) {
        guard canInteract, let game, !game.isGiven(cell) else { return }
        selected = cell
        let current = game.values[cell]
        let next = up ? min(9, current + 1) : max(0, current - 1)
        guard next != current else { return }
        if next == 0 { erase() } else { place(next, at: cell) }
    }

    private func place(_ digit: Int, at cell: Int) {
        guard var game, let outcome = game.enter(digit, at: cell) else { return }
        self.game = game
        popCount[cell] += 1
        react(to: outcome, at: cell)
    }

    func erase() {
        guard canInteract, var game, let cell = selected, game.erase(at: cell) else { return }
        self.game = game
        Feedback.play(.pop)
        persist()
    }

    func undo() {
        guard canUndo, var game else { return }
        let cells = game.undo()
        self.game = game
        if let first = cells.first { selected = first }
        Feedback.play(.flip)
        persist()
    }

    func hint() {
        guard canInteract, var game, let (hint, outcome) = game.applyHint() else { return }
        self.game = game
        selected = hint.cell
        popCount[hint.cell] += 1
        showBanner(hint)
        react(to: outcome, at: hint.cell)
    }

    func togglePause() {
        guard game != nil, !isSolved, !isGenerating else { return }
        isPaused.toggle()
        Feedback.play(.tap)
        updateClock()
        persist()
    }

    func newGame(_ difficulty: Difficulty) {
        if let game, !isSolved, game.hasProgress {
            // An abandoned game with progress counts as played, not won.
            stats.record(gameID, variant: game.difficulty.rawValue, won: false, time: clock.elapsed())
        }
        store.remove(key: gameID.saveKey)
        startGeneration(difficulty)
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateClock()
        if !active { persist() }
    }

    // MARK: - Internals

    private func startGeneration(_ difficulty: Difficulty) {
        self.difficulty = difficulty
        UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        generation += 1
        let token = generation
        isGenerating = true
        isSolved = false
        showWin = false
        isPaused = false
        isNewBest = false
        hintBanner = nil
        selected = nil
        clock = GameClock()
        let seed = UInt64.random(in: .min ... .max)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.generation == token, self.isGenerating else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.showSpinner = true }
        }
        Task { [weak self] in
            let puzzle = await Task.detached(priority: .userInitiated) {
                Sudoku.generate(difficulty: difficulty, seed: seed)
            }.value
            guard let self, self.generation == token else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.game = Sudoku.Game(puzzle: puzzle)
                self.isGenerating = false
                self.showSpinner = false
            }
            self.updateClock()
            // Ripple across the fresh board.
            self.wave(cells: Array(0..<Sudoku.cellCount), from: 0, step: 0.018)
        }
    }

    private func react(to outcome: Sudoku.Outcome, at cell: Int) {
        if outcome.solved {
            finish(at: cell)
        } else if outcome.conflicts {
            Feedback.play(.invalid)
        } else if !outcome.completedUnits.isEmpty {
            Feedback.play(.clear)
            let cells = Set(outcome.completedUnits.flatMap(\.cells))
            wave(cells: Array(cells), from: cell, step: 0.045)
        } else {
            Feedback.play(.place)
        }
        persist()
    }

    private func finish(at cell: Int) {
        isSolved = true
        selected = nil
        hintBanner = nil
        notesMode = false
        clock.pause()
        let time = clock.elapsed()
        let previousBest = bestTime
        isNewBest = previousBest.map { time < $0 } ?? true
        stats.record(gameID, variant: difficulty.rawValue, won: true, time: time)
        store.remove(key: gameID.saveKey)
        Feedback.play(.win)
        wave(cells: Array(0..<Sudoku.cellCount), from: cell, step: 0.04)
        let token = generation
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, self.generation == token, self.isSolved else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.showWin = true }
        }
    }

    /// Replays the completion wave on `cells`, rippling outward from `origin`.
    private func wave(cells: [Int], from origin: Int, step: Double) {
        let r0 = Sudoku.row(of: origin), c0 = Sudoku.column(of: origin)
        for cell in cells {
            let distance = max(abs(Sudoku.row(of: cell) - r0), abs(Sudoku.column(of: cell) - c0))
            let diagonal = Sudoku.row(of: cell) + Sudoku.column(of: cell)
            // Single units ripple from the placed cell; the whole board sweeps diagonally.
            waveDelay[cell] = Double(cells.count == Sudoku.cellCount ? diagonal : distance) * step
            waveCount[cell] += 1
        }
    }

    private func showBanner(_ hint: Sudoku.Hint) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hintBanner = hint }
        bannerToken += 1
        let token = bannerToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard let self, self.bannerToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.hintBanner = nil }
        }
    }

    private func updateClock() {
        if isActive, game != nil, !isGenerating, !isPaused, !isSolved {
            clock.start()
        } else {
            clock.pause()
        }
    }

    private func persist() {
        guard let game, !isSolved, !isGenerating else { return }
        // An untouched puzzle isn't a game in progress (no "Continue Playing", no erase prompt).
        guard game.hasProgress else {
            store.remove(key: gameID.saveKey)
            return
        }
        store.save(Saved(game: game, clock: clock, selected: selected, notesMode: notesMode, isPaused: isPaused),
                   key: gameID.saveKey)
    }
}
