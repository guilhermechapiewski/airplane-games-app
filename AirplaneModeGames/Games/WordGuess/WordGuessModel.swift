import SwiftUI
import GameLogic

/// Who picks the secret word.
enum WordGuessMode: String, Codable, CaseIterable {
    case computer, friend

    var title: String {
        switch self {
        case .computer: "vs. Computer"
        case .friend: "Pass & Play"
        }
    }
}

/// A two-player Pass & Play match: players take turns picking the word for each other.
struct WordGuessMatch: Codable, Equatable {
    var names: [String] = ["Player 1", "Player 2"]
    var scores: [Int] = [0, 0]
    /// Index of the player who picks the secret word this round.
    var setter = 0
    var round = 1

    var guesser: Int { 1 - setter }
    var setterName: String { names[setter] }
    var guesserName: String { names[guesser] }

    /// Points for solving: 6 for a first-try solve down to 1 on the last guess.
    static func points(forSolvingIn guesses: Int) -> Int { max(0, WordGuess.maxGuesses + 1 - guesses) }
}

@MainActor @Observable
final class WordGuessModel {
    typealias Logic = WordGuess

    enum Phase: String, Codable {
        /// Pass & Play: enter player names.
        case names
        /// Pass & Play: the setter types the secret word.
        case secret
        /// Pass & Play: the phone is being handed to the guesser.
        case handoff
        case playing
        /// Pass & Play: round finished, scoreboard showing.
        case roundOver
    }

    private struct Saved: Codable {
        var mode: WordGuessMode
        var phase: Phase
        var state: Logic.State
        var match: WordGuessMatch
        /// Optional so saves from before hints existed still load.
        var hintsUsed: Int?
    }

    private(set) var mode: WordGuessMode = .computer
    private(set) var phase: Phase = .playing
    private(set) var state: Logic.State
    private(set) var match = WordGuessMatch()

    // Presentation state
    /// Keyboard colors lag behind `state` until the flip animation has revealed the row.
    private(set) var keyboard: [Character: Logic.LetterState] = [:]
    /// Number of rows whose tiles show their colors.
    private(set) var revealedRows = 0
    private(set) var isRevealing = false
    private(set) var shakeToken = 0
    private(set) var bounceToken = 0
    private(set) var popToken = 0
    private(set) var toast: String?
    private(set) var showResult = false
    private var toastToken = 0
    private var revealToken = 0
    /// The suggested next guess, while its card is showing.
    private(set) var hint: Logic.Suggestion?
    /// Hints asked for this game (shown on the result card).
    private(set) var hintsUsed = 0
    /// A hint is being worked out.
    private(set) var isThinking = false
    /// The last suggestion and how many guesses it was for: asking again before the next guess
    /// shows it again without counting another hint.
    private var lastHint: (guesses: Int, suggestion: Logic.Suggestion)?
    private var hintToken = 0

    var hardModePreference: Bool {
        didSet {
            UserDefaults.standard.set(hardModePreference, forKey: Self.hardModeKey)
            if !state.isOver, state.guesses.isEmpty {
                state = Logic.State(answer: state.answer, hardMode: hardModePreference)
                persist()
            }
        }
    }

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.wordGuess
    static let hardModeKey = "wordGuess.hardMode"
    static let highContrastKey = "wordGuess.highContrast"
    static let distributionKey = "wordGuess.distribution"
    static let revealStep = 0.28
    static let flipDuration = 0.36

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let hard = UserDefaults.standard.bool(forKey: Self.hardModeKey)
        distribution = store.load([Int].self, key: Self.distributionKey) ?? Array(repeating: 0, count: Logic.maxGuesses)
        hardModePreference = hard
        if let saved = store.load(Saved.self, key: GameID.wordGuess.saveKey) {
            mode = saved.mode
            phase = saved.phase
            state = saved.state
            match = saved.match
            hintsUsed = saved.hintsUsed ?? 0
            revealedRows = saved.state.guesses.count
            keyboard = saved.state.keyboard
            if state.isOver {
                if mode == .friend {
                    phase = .roundOver
                    showResult = true
                } else {
                    state = Self.computerGame(hard: hard)
                    revealedRows = 0
                    keyboard = [:]
                    hintsUsed = 0
                }
            }
        } else {
            state = Self.computerGame(hard: hard)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoState") { loadDemo() }
        #endif
    }

    #if DEBUG
    /// A mid-game board for screenshots (`-demoState`).
    private func loadDemo() {
        var demo = Logic.State(answer: "crane")
        for word in ["slate", "prune", "grace"] {
            for ch in word { demo.type(ch) }
            _ = try? demo.submit()
        }
        for ch in "cr" { demo.type(ch) }
        state = demo
        revealedRows = demo.guesses.count
        keyboard = demo.keyboard
        if ProcessInfo.processInfo.arguments.contains("-demoWon") {
            for ch in "ane" { type(ch) }
            submit()
        }
    }
    #endif

    private static func computerGame(hard: Bool) -> Logic.State {
        var rng = SystemRandomNumberGenerator()
        return Logic.State(answer: WordLists.randomAnswer(using: &rng), hardMode: hard)
    }

    // MARK: Derived

    var canType: Bool { phase == .playing && !state.isOver && !isRevealing }
    var statsVariant: String { mode.rawValue }

    private(set) var distribution: [Int] = []

    var statusLine: String {
        switch mode {
        case .computer:
            return state.hardMode ? "vs. Computer · Hard Mode" : "vs. Computer"
        case .friend:
            return "\(match.guesserName) is guessing \(match.setterName)'s word"
        }
    }

    // MARK: Input

    func type(_ letter: Character) {
        guard canType, state.type(letter) else { return }
        dismissHint()
        popToken += 1
        Feedback.play(.tap)
        persist()
    }

    func deleteLetter() {
        guard canType, state.deleteLetter() else { return }
        Haptics.tap()
        persist()
    }

    func submit() {
        guard canType else { return }
        dismissHint()
        do {
            _ = try state.submit()
        } catch {
            reject(error.message)
            return
        }
        let row = state.guesses.count - 1
        isRevealing = true
        Feedback.play(.flip)
        persist()
        let total = Self.revealStep * Double(Logic.wordLength - 1) + Self.flipDuration
        revealedRows = row + 1
        revealToken += 1
        let token = revealToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(total))
            guard let self, self.revealToken == token else { return }
            self.finishReveal()
        }
    }

    /// Ends the tile flip: colors the keyboard and, if the guess ended the game, records the result.
    private func finishReveal() {
        guard isRevealing else { return }
        isRevealing = false
        withAnimation(.easeOut(duration: 0.2)) { keyboard = state.keyboard }
        switch state.status {
        case .playing:
            break
        case .won:
            bounceToken += 1
            Feedback.play(.win)
            finishGame(won: true)
        case .lost:
            Feedback.play(.lose)
            showToast(state.answer.uppercased(), duration: 2.0)
            finishGame(won: false)
        }
    }

    private func reject(_ message: String) {
        shakeToken += 1
        Feedback.play(.invalid)
        showToast(message)
    }

    func showToast(_ message: String, duration: Double = 1.4) {
        toastToken += 1
        let token = toastToken
        withAnimation(.snappy(duration: 0.2)) { toast = message }
        AccessibilityNotification.Announcement(message).post()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.toastToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
        }
    }

    // MARK: Hints

    var canHint: Bool { canType && !isThinking }

    /// Works out a good next guess (off the main actor) and shows it with its reasoning.
    func showHint() {
        guard canHint else { return }
        let count = state.guesses.count
        if let last = lastHint, last.guesses == count {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { hint = last.suggestion }
            Feedback.play(.select)
            return
        }
        hintToken += 1
        let token = hintToken
        let guesses = state.guesses, hard = state.hardMode, friend = mode == .friend
        isThinking = true
        Task { @MainActor [weak self] in
            let suggestion = await Self.suggestion(after: guesses, hardMode: hard, friendsWord: friend)
            guard let self, self.hintToken == token else { return }
            self.isThinking = false
            guard let suggestion, self.canType, self.state.guesses.count == count else { return }
            self.hintsUsed += 1
            self.lastHint = (count, suggestion)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.hint = suggestion }
            Feedback.play(.select)
            AccessibilityNotification.Announcement("\(suggestion.title). \(suggestion.explanation)").post()
            self.persist()
        }
    }

    /// Types the suggested word into the current row (the player still presses Enter).
    func typeHint() {
        guard let word = hint?.word, canType else { return }
        dismissHint()
        while state.deleteLetter() {}
        for ch in word { state.type(ch) }
        popToken += 1
        Feedback.play(.tap)
        persist()
    }

    func dismissHint() {
        guard hint != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { hint = nil }
    }

    /// A friend's word may not be a common answer, so their games can fall back to every valid word.
    nonisolated private static func suggestion(after guesses: [Logic.Guess], hardMode: Bool,
                                               friendsWord: Bool) async -> Logic.Suggestion? {
        await Task.detached(priority: .userInitiated) {
            Logic.suggestion(after: guesses, hardMode: hardMode, answers: WordLists.answers,
                             allWords: friendsWord ? WordLists.validGuesses.sorted() : [])
        }.value
    }

    // MARK: Game end

    private func finishGame(won: Bool) {
        let guesses = state.guesses.count
        stats.record(game, variant: statsVariant, won: won, score: nil)
        if mode == .computer {
            if won, guesses >= 1, guesses <= distribution.count { distribution[guesses - 1] += 1 }
            store.save(distribution, key: Self.distributionKey)
        } else {
            if won { match.scores[match.guesser] += WordGuessMatch.points(forSolvingIn: guesses) }
            phase = .roundOver
        }
        persist()
        let delay = won ? 1.1 : 1.6
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.state.isOver else { return }
            withAnimation { self.showResult = true }
        }
    }

    // MARK: New games

    func newComputerGame() {
        abandonIfNeeded()
        mode = .computer
        phase = .playing
        reset(to: Self.computerGame(hard: hardModePreference))
        store.remove(key: game.saveKey)
    }

    /// Starts a fresh Pass & Play match (asks for names first).
    func newFriendMatch() {
        abandonIfNeeded()
        let names = match.names
        mode = .friend
        match = WordGuessMatch()
        match.names = names
        phase = .names
        reset(to: Self.computerGame(hard: hardModePreference))
        persist()
    }

    /// Starts the next Pass & Play round with roles swapped.
    func nextRound() {
        guard mode == .friend else { return }
        match.setter = match.guesser
        match.round += 1
        phase = .secret
        reset(to: state)
        revealedRows = 0
        keyboard = [:]
        persist()
    }

    func confirmNames(_ first: String, _ second: String) {
        func clean(_ s: String, _ fallback: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? fallback : String(t.prefix(16))
        }
        match.names = [clean(first, "Player 1"), clean(second, "Player 2")]
        phase = .secret
        Feedback.play(.select)
        persist()
    }

    /// Validates a secret word typed by the setter; returns an error message or `nil`.
    static func secretProblem(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespaces).lowercased()
        if w.count != Logic.wordLength || !w.allSatisfy({ $0.isASCII && $0.isLetter }) {
            return "Enter exactly 5 letters"
        }
        return WordLists.isValidGuess(w) ? nil : "That's not in the word list"
    }

    func setSecret(_ word: String) {
        guard Self.secretProblem(word) == nil else { return }
        let w = word.trimmingCharacters(in: .whitespaces).lowercased()
        reset(to: Logic.State(answer: w, hardMode: hardModePreference))
        phase = .handoff
        Feedback.play(.place)
        persist()
    }

    func beginGuessing() {
        phase = .playing
        Feedback.play(.select)
        persist()
    }

    private func reset(to newState: Logic.State) {
        state = newState
        keyboard = [:]
        revealedRows = 0
        isRevealing = false
        showResult = false
        toast = nil
        hint = nil
        hintsUsed = 0
        lastHint = nil
        hintToken += 1
        isThinking = false
    }

    /// Counts a computer game abandoned mid-way as a loss (it had guesses).
    private func abandonIfNeeded() {
        if mode == .computer, phase == .playing, !state.isOver, !state.guesses.isEmpty {
            stats.record(game, variant: statsVariant, won: false)
        }
    }

    func reopenResult() {
        showResult = true
    }

    func dismissResult() {
        withAnimation { showResult = false }
    }

    func setActive(_ active: Bool) {
        guard !active else { return }
        // Leaving while the last row flips must still record a finished game (the model may be
        // released before the reveal ends).
        if isRevealing { finishReveal() }
        persist()
    }

    private func persist() {
        if mode == .computer && (state.isOver || !state.hasProgress) {
            store.remove(key: game.saveKey)
        } else {
            store.save(Saved(mode: mode, phase: phase, state: state, match: match, hintsUsed: hintsUsed), key: game.saveKey)
        }
    }
}
