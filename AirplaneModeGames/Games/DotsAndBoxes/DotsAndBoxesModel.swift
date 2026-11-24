import SwiftUI
import GameLogic

/// Who the player faces and on what board.
struct DotsSetup: Codable, Equatable {
    enum Opponent: String, Codable, CaseIterable, Identifiable {
        case computer, friend
        var id: String { rawValue }
        var title: String { self == .computer ? "vs. Computer" : "Pass & Play" }
    }

    static let sizes = [3, 4, 6]

    var opponent: Opponent = .computer
    var level: DotsAndBoxes.Level = .medium
    /// Boxes per side.
    var size = 4

    var isComputer: Bool { opponent == .computer }
}

/// Wins, losses and ties against one computer level, derived from `StatsStore` (ties are kept
/// in a companion variant, so "Reset All Statistics" clears them too).
struct DotsRecord: Equatable {
    var wins = 0, losses = 0, ties = 0
    var total: Int { wins + losses + ties }
}

@MainActor @Observable
final class DotsAndBoxesModel {
    typealias Player = DotsAndBoxes.Player
    typealias Line = DotsAndBoxes.Line

    private struct Saved: Codable {
        var game: DotsAndBoxes.Game
        var setup: DotsSetup
        var clock: GameClock
    }

    private(set) var game: DotsAndBoxes.Game
    private(set) var setup: DotsSetup
    private(set) var isThinking = false
    var showResult = false
    var showSetup = false
    /// Bumped on every board change.
    private(set) var changeCount = 0

    private var clock = GameClock()
    private var aiTask: Task<Void, Never>?
    private var generation = 0
    private var isActive = false
    private let store: GameStore
    private let stats: StatsStore
    let gameID = GameID.dotsAndBoxes

    /// The human in a computer game.
    static let human: Player = .one
    private static let lastSetupKey = "dotsAndBoxes.lastSetup"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        if let saved = store.load(Saved.self, key: GameID.dotsAndBoxes.saveKey), !saved.game.isOver {
            game = saved.game
            setup = saved.setup
            clock = saved.clock
        } else {
            let setup = Self.lastSetup
            self.setup = setup
            game = DotsAndBoxes.Game(rows: setup.size, cols: setup.size)
            showSetup = true
        }
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// `-dotsDemo <size> <moves> [friend]` plays a seeded game part-way for screenshots.
    private func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dotsDemo"), i + 2 < args.count,
              let size = Int(args[i + 1]), let moves = Int(args[i + 2]) else { return }
        setup.size = size
        if args.contains("-dotsFriend") { setup.opponent = .friend }
        game = DotsAndBoxes.Game(rows: size, cols: size)
        var rng = SeededRandom(seed: 42)
        for _ in 0..<moves where !game.isOver {
            if let line = DotsAndBoxes.AI.chooseMove(for: game, level: .medium, rng: &rng) { game.play(line) }
        }
        // Leave the human to move.
        while setup.isComputer && game.current != Self.human && !game.isOver,
              let line = DotsAndBoxes.AI.chooseMove(for: game, level: .medium, rng: &rng) {
            game.play(line)
        }
        showSetup = false
    }
    #endif

    static var lastSetup: DotsSetup {
        guard let data = UserDefaults.standard.data(forKey: lastSetupKey),
              let s = try? JSONDecoder().decode(DotsSetup.self, from: data) else { return DotsSetup() }
        return s
    }

    // MARK: Derived state

    var isOver: Bool { game.isOver }
    var current: Player { game.current }
    var lastLine: Line? { game.lastTurn?.line }

    var isHumanTurn: Bool {
        !isOver && (!setup.isComputer || game.current == Self.human)
    }

    func isComputer(_ player: Player) -> Bool { setup.isComputer && player != Self.human }

    func name(for player: Player) -> String {
        if setup.isComputer { return player == Self.human ? "You" : "Computer" }
        return player == .one ? "Player 1" : "Player 2"
    }

    /// The letter shown in a claimed box.
    func initial(for player: Player) -> String {
        if setup.isComputer { return player == Self.human ? "Y" : "C" }
        return player == .one ? "1" : "2"
    }

    var canUndo: Bool {
        guard !isOver else { return false }
        if setup.isComputer { return game.history.contains { $0.player == Self.human } }
        return !game.history.isEmpty
    }

    var statusText: String {
        if isOver { return outcomeTitle }
        if setup.isComputer {
            return game.current == Self.human ? (justClaimed ? "Box! Go again" : "Your turn") : "Computer's turn"
        }
        return "\(name(for: game.current))" + (justClaimed ? " — go again" : "'s turn")
    }

    /// The player to move just completed a box (and so moves again).
    private var justClaimed: Bool {
        guard let last = game.lastTurn else { return false }
        return !last.claimed.isEmpty && last.player == game.current
    }

    var outcomeTitle: String {
        guard let winner = game.winner else { return "It's a Tie" }
        if setup.isComputer { return winner == Self.human ? "You Won!" : "You Lost" }
        return "\(name(for: winner)) Wins"
    }

    /// nil = tie; true = a win worth celebrating (any decisive pass & play result).
    var resultIsWin: Bool? {
        guard let winner = game.winner else { return nil }
        return setup.isComputer ? winner == Self.human : true
    }

    func record(for level: DotsAndBoxes.Level) -> DotsRecord {
        let main = stats.stats(for: gameID, variant: Self.statsKey(level))
        let ties = stats.stats(for: gameID, variant: Self.tieKey(level)).played
        return DotsRecord(wins: main.won, losses: max(0, main.played - main.won - ties), ties: ties)
    }

    static func statsKey(_ level: DotsAndBoxes.Level) -> String { "level\(level.rawValue)" }
    static func tieKey(_ level: DotsAndBoxes.Level) -> String { "level\(level.rawValue).ties" }

    // MARK: Input

    /// Whether a touch may draw this line right now.
    func canDraw(_ line: Line) -> Bool {
        isHumanTurn && game.contains(line) && !game.isDrawn(line)
    }

    func tap(_ line: Line) {
        guard canDraw(line) else { return }
        play(line)
    }

    // MARK: Moves

    private func play(_ line: Line, byComputer: Bool = false) {
        let mover = game.current
        guard let turn = game.play(line) else { return }
        generation += 1
        changeCount += 1
        clock.start()

        if game.isOver {
            Feedback.play(turn.claimed.isEmpty ? .place : .pop)
        } else if !turn.claimed.isEmpty {
            Feedback.play(.pop)
        } else if !byComputer {
            Feedback.play(.place)
        } else {
            Feedback.play(.tap)
        }
        announce(turn, by: mover, byComputer: byComputer)

        if game.isOver {
            finish()
        } else {
            scheduleComputerIfNeeded(followUp: !turn.claimed.isEmpty)
        }
        persist()
    }

    /// Starts the computer's next line if it's its turn. A follow-up (another line in the same
    /// turn after claiming a box) comes quicker than the first reply.
    private func scheduleComputerIfNeeded(followUp: Bool = false) {
        guard setup.isComputer, !isOver, game.current != Self.human, isActive else { return }
        aiTask?.cancel()
        isThinking = true
        let snapshot = game
        let level = setup.level
        let token = generation
        let pause: Duration = followUp ? .milliseconds(300) : .milliseconds(550)
        aiTask = Task { [weak self] in
            let start = ContinuousClock.now
            let search = Task.detached(priority: .userInitiated) {
                var rng = SeededRandom()
                return DotsAndBoxes.AI.chooseMove(for: snapshot, level: level, rng: &rng)
            }
            let line = await withTaskCancellationHandler {
                await search.value
            } onCancel: {
                search.cancel()
            }
            // A short, natural pause so replies don't feel abrupt.
            if ContinuousClock.now - start < pause {
                try? await Task.sleep(until: start + pause, clock: .continuous)
            }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.isThinking = false
            guard let line else { return }
            self.play(line, byComputer: true)
        }
    }

    private func cancelComputer() {
        aiTask?.cancel()
        aiTask = nil
        isThinking = false
        generation += 1
    }

    func undo() {
        guard canUndo else { return }
        cancelComputer()
        if setup.isComputer {
            // Take back the computer's lines, then the player's last line.
            while let last = game.lastTurn, last.player != Self.human { game.undo() }
            game.undo()
        } else {
            game.undo()
        }
        changeCount += 1
        Feedback.play(.flip)
        announce("Undone. " + statusText)
        persist()
        // Undoing can't land on the computer's turn, but be safe.
        scheduleComputerIfNeeded()
    }

    func newGame(_ newSetup: DotsSetup) {
        if let data = try? JSONEncoder().encode(newSetup) {
            UserDefaults.standard.set(data, forKey: Self.lastSetupKey)
        }
        start(newSetup, firstPlayer: .one)
    }

    /// Same settings again; the other player starts.
    func rematch() {
        start(setup, firstPlayer: game.history.isEmpty ? game.firstPlayer : game.firstPlayer.other)
    }

    private func start(_ newSetup: DotsSetup, firstPlayer: Player) {
        cancelComputer()
        setup = newSetup
        game = DotsAndBoxes.Game(rows: newSetup.size, cols: newSetup.size, firstPlayer: firstPlayer)
        showResult = false
        clock = GameClock()
        changeCount += 1
        store.remove(key: gameID.saveKey)
        Feedback.play(.flip)
        scheduleComputerIfNeeded()
        persist()
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            if !isOver && !game.history.isEmpty { clock.start() }
            if !isThinking { scheduleComputerIfNeeded() }
        } else {
            clock.pause()
            cancelComputer()
            persist()
        }
    }

    private func finish() {
        clock.pause()
        isThinking = false
        let time = clock.elapsed()
        let winner = game.winner
        if setup.isComputer {
            let won = winner == Self.human
            stats.record(gameID, variant: Self.statsKey(setup.level), won: won, time: time)
            if winner == nil { stats.record(gameID, variant: Self.tieKey(setup.level), won: false) }
            Feedback.play(winner == nil ? .clear : (won ? .win : .lose))
        } else {
            stats.record(gameID, variant: "passAndPlay", won: winner != nil, time: time)
            Feedback.play(winner == nil ? .clear : .win)
        }
        announce("\(outcomeTitle). \(scoreLine)")
        let token = changeCount
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.changeCount == token, self.isOver else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.showResult = true }
        }
    }

    var scoreLine: String {
        "\(name(for: .one)) \(game.score(.one)), \(name(for: .two)) \(game.score(.two))"
    }

    private func persist() {
        if isOver || game.history.isEmpty {
            store.remove(key: gameID.saveKey)
        } else {
            store.save(Saved(game: game, setup: setup, clock: clock), key: gameID.saveKey)
        }
    }

    // MARK: Accessibility

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    private func announce(_ turn: DotsAndBoxes.Turn, by mover: Player, byComputer: Bool) {
        var parts: [String] = []
        if byComputer { parts.append("Computer drew " + Self.spokenName(of: turn.line)) }
        if !turn.claimed.isEmpty {
            let boxes = turn.claimed.count == 1 ? "a box" : "two boxes"
            parts.append(setup.isComputer ? (mover == Self.human ? "You claimed \(boxes)" : "Computer claimed \(boxes)")
                                          : "\(name(for: mover)) claimed \(boxes)")
        }
        if !game.isOver {
            if game.current != mover {
                parts.append(setup.isComputer ? (game.current == Self.human ? "Your turn" : "Computer's turn")
                                              : "\(name(for: game.current))'s turn")
            } else if !turn.claimed.isEmpty {
                parts.append("Go again")
            }
        }
        guard !parts.isEmpty else { return }
        announce(parts.joined(separator: ". "))
    }

    /// "line between row 2 column 3 and row 2 column 4" (1-based dot coordinates).
    static func spokenName(of line: Line) -> String {
        let (a, b) = line.dots
        return "line between row \(a.row + 1) column \(a.col + 1) and row \(b.row + 1) column \(b.col + 1)"
    }
}
