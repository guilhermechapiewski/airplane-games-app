import SwiftUI
import GameLogic

enum HangmanMode: String, Codable {
    case computer, friend
}

@MainActor @Observable
final class HangmanModel {
    typealias Logic = Hangman

    enum Phase: String, Codable {
        /// Pass & Play: the friend types a word or phrase.
        case secret
        /// Pass & Play: handing the phone over.
        case handoff
        case playing
    }

    private struct Saved: Codable {
        var mode: HangmanMode
        var phase: Phase
        var state: Logic.State
        var difficulty: Difficulty
        var categoryID: String?
    }

    private(set) var mode: HangmanMode = .computer
    private(set) var phase: Phase = .playing
    private(set) var state: Logic.State
    private(set) var difficulty: Difficulty
    /// `nil` means a random category each game.
    private(set) var categoryID: String?
    private(set) var showResult = false
    /// Bumped on each miss / hit so views can animate.
    private(set) var missToken = 0
    private(set) var hitToken = 0

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.hangman
    static let difficulties: [Difficulty] = [.easy, .medium, .hard]
    private static let difficultyKey = "hangman.difficulty"
    private static let categoryKey = "hangman.category"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let defaults = UserDefaults.standard
        let savedDifficulty = Difficulty(rawValue: defaults.string(forKey: Self.difficultyKey) ?? "") ?? .medium
        let savedCategory = defaults.string(forKey: Self.categoryKey).flatMap { WordCategory.named($0)?.id }
        difficulty = savedDifficulty
        categoryID = savedCategory
        if let saved = store.load(Saved.self, key: GameID.hangman.saveKey), !saved.state.isOver {
            mode = saved.mode
            phase = saved.phase
            state = saved.state
            difficulty = saved.difficulty
            categoryID = saved.categoryID
        } else {
            state = Self.computerPuzzle(categoryID: savedCategory, difficulty: savedDifficulty)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoState") {
            var demo = Logic.State(phrase: "hot air balloon", category: "Travel")
            for c in "aeoqrz" { demo.guess(c) }
            state = demo
            if ProcessInfo.processInfo.arguments.contains("-demoLost") {
                for c in "xjkv" { guess(c) }
            }
        }
        #endif
    }

    private static func computerPuzzle(categoryID: String?, difficulty: Difficulty) -> Logic.State {
        var rng = SystemRandomNumberGenerator()
        return Logic.randomPuzzle(category: categoryID.flatMap(WordCategory.named), difficulty: difficulty, using: &rng)
    }

    // MARK: Derived

    var statsVariant: String { mode == .friend ? "friend" : difficulty.rawValue }
    var categoryTitle: String { categoryID.flatMap(WordCategory.named)?.title ?? "Random" }
    var canGuess: Bool { phase == .playing && !state.isOver }

    func keyState(_ letter: Character) -> HangmanKeyState {
        guard state.guessed.contains(letter) else { return .unused }
        return state.phrase.contains(letter) ? .hit : .miss
    }

    // MARK: Play

    func guess(_ letter: Character) {
        guard canGuess else { return }
        let result = state.guess(letter)
        switch result {
        case .ignored:
            return
        case .hit:
            hitToken += 1
            Feedback.play(.pop)
        case .miss:
            missToken += 1
            Feedback.play(.invalid)
        }
        if state.isOver { finish() }
        persist()
    }

    private func finish() {
        let won = state.status == .won
        stats.record(game, variant: statsVariant, won: won)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(won ? 0.6 : 1.1))
            guard let self, self.state.isOver else { return }
            Feedback.play(won ? .win : .lose)
            withAnimation { self.showResult = true }
        }
    }

    // MARK: New games

    func newComputerGame(difficulty: Difficulty? = nil) {
        abandonIfNeeded()
        if let difficulty {
            self.difficulty = difficulty
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
        mode = .computer
        phase = .playing
        reset(Self.computerPuzzle(categoryID: categoryID, difficulty: self.difficulty))
        store.remove(key: game.saveKey)
    }

    /// Chooses a category (`nil` = random) and starts a computer game.
    func chooseCategory(_ id: String?) {
        categoryID = id
        UserDefaults.standard.set(id, forKey: Self.categoryKey)
        newComputerGame()
    }

    func newFriendGame() {
        abandonIfNeeded()
        mode = .friend
        phase = .secret
        reset(state)
        persist()
    }

    func setSecret(phrase: String, hint: String) {
        guard Logic.problem(with: phrase) == nil else { return }
        reset(Logic.State(phrase: phrase, category: nil, hint: hint))
        phase = .handoff
        Feedback.play(.place)
        persist()
    }

    func beginGuessing() {
        phase = .playing
        Feedback.play(.select)
        persist()
    }

    func playAgain() {
        if mode == .friend { newFriendGame() } else { newComputerGame() }
    }

    func dismissResult() {
        withAnimation { showResult = false }
    }

    func reopenResult() {
        withAnimation { showResult = true }
    }

    private func reset(_ newState: Logic.State) {
        state = newState
        showResult = false
    }

    private func abandonIfNeeded() {
        if phase == .playing, !state.isOver, !state.guessed.isEmpty {
            stats.record(game, variant: statsVariant, won: false)
        }
    }

    func setActive(_ active: Bool) {
        if !active { persist() }
    }

    private func persist() {
        let hasProgress = phase != .playing || !state.guessed.isEmpty
        if state.isOver || !hasProgress {
            store.remove(key: game.saveKey)
        } else {
            store.save(Saved(mode: mode, phase: phase, state: state, difficulty: difficulty, categoryID: categoryID),
                       key: game.saveKey)
        }
    }
}

enum HangmanKeyState {
    case unused, hit, miss
}
