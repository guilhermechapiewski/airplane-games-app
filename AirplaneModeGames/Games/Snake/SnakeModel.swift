import SwiftUI
import GameLogic

@MainActor @Observable
final class SnakeModel {
    typealias Logic = Snake

    enum Phase: Equatable {
        /// A fresh game waiting for the player to start.
        case ready
        case countdown(Int)
        case running
        case paused
        case over
    }

    /// A short ripple where food was eaten.
    struct EatEvent: Identifiable {
        let id = UUID()
        let point: GridPoint
        let date: Date
    }

    private struct Saved: Codable {
        var state: Logic.State
        var speed: Logic.Speed
        /// How far into the current tick the snake was drawn when paused (0…1).
        var progress: Double
        var previousBody: [GridPoint]
        var clock: GameClock
    }

    private enum Keys {
        static let speed = "snake.speed"
        static let wallMode = "snake.wallMode"
        static let boardSize = "snake.boardSize"
    }

    /// Statistics are kept per speed and board size. The classic board keeps the plain speed
    /// key, so its scores carry over from before board sizes existed.
    static func statsVariant(speed: Logic.Speed, size: Logic.BoardSize) -> String {
        size == .classic ? speed.rawValue : "\(speed.rawValue)-\(size.rawValue)"
    }

    private(set) var state: Logic.State
    /// Body before the latest tick, for interpolated drawing.
    private(set) var previousBody: [GridPoint]
    /// When the latest tick happened (start of the current interpolation).
    private(set) var lastTick = Date.now
    /// Interpolation progress frozen while not running.
    private(set) var frozenProgress: Double = 1
    private(set) var phase: Phase = .ready
    private(set) var speed: Logic.Speed
    private(set) var eatEvents: [EatEvent] = []
    private(set) var foodBorn = Date.distantPast
    private(set) var deathDate: Date?
    private(set) var showGameOver = false
    private(set) var clock = GameClock()
    /// Best score for this speed before the current game began.
    private(set) var bestAtStart: Int

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    private let store: GameStore
    private let stats: StatsStore
    private let defaults: UserDefaults
    let game = GameID.snake

    init(store: GameStore = .shared, stats: StatsStore = .shared, defaults: UserDefaults = .standard) {
        self.store = store
        self.stats = stats
        self.defaults = defaults
        let savedSpeed = defaults.string(forKey: Keys.speed).flatMap(Logic.Speed.init(rawValue:)) ?? .normal
        let savedMode = defaults.string(forKey: Keys.wallMode).flatMap(Logic.WallMode.init(rawValue:)) ?? .walls
        let savedSize = defaults.string(forKey: Keys.boardSize).flatMap(Logic.BoardSize.init(rawValue:)) ?? .classic
        if let saved = store.load(Saved.self, key: GameID.snake.saveKey), !saved.state.isOver {
            state = saved.state
            speed = saved.speed
            previousBody = saved.previousBody
            frozenProgress = saved.progress
            clock = saved.clock
            phase = .paused
            bestAtStart = stats.stats(for: .snake, variant: Self.statsVariant(
                speed: saved.speed, size: saved.state.boardSize ?? .classic)).bestScore ?? 0
        } else {
            let fresh = Logic.State.newGame(size: savedSize, wallMode: savedMode)
            state = fresh
            speed = savedSpeed
            previousBody = fresh.body
            bestAtStart = stats.stats(for: .snake, variant: Self.statsVariant(speed: savedSpeed, size: savedSize)).bestScore ?? 0
        }
        foodBorn = .now
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-snakeDemo") { loadDemo() }
        #endif
    }

    #if DEBUG
    /// A long, winding snake in wrap mode for screenshots (`-snakeDemo`).
    private func loadDemo() {
        var body: [GridPoint] = (2...9).reversed().map { GridPoint(row: 4, col: $0) }
        body += [GridPoint(row: 5, col: 2)]
        body += (2...11).map { GridPoint(row: 6, col: $0) }
        body += [GridPoint(row: 7, col: 11), GridPoint(row: 8, col: 11)]
        body += (5...11).reversed().map { GridPoint(row: 9, col: $0) }
        state = Logic.State(width: Logic.defaultSize, height: Logic.defaultSize, wallMode: .wrap, body: body,
                            direction: .up, food: GridPoint(row: 1, col: 9), seed: 7, score: body.count - 3)
        previousBody = body
        startCountdown()
    }
    #endif

    var wallMode: Logic.WallMode { state.wallMode }
    var boardSize: Logic.BoardSize { state.boardSize ?? .classic }
    var statsVariant: String { Self.statsVariant(speed: speed, size: boardSize) }
    var best: Int { max(stats.stats(for: game, variant: statsVariant).bestScore ?? 0, state.score) }
    var isNewBest: Bool { bestAtStart > 0 && state.score > bestAtStart }
    var isRunning: Bool { phase == .running }

    /// Interpolation progress (0…1) between `previousBody` and `state.body`.
    func progress(at date: Date) -> Double {
        guard phase == .running else { return frozenProgress }
        return min(1, max(0, date.timeIntervalSince(lastTick) / speed.interval))
    }

    // MARK: Setup

    /// Changes speed / edges / board size before the first move.
    func configure(speed newSpeed: Logic.Speed? = nil, wallMode newMode: Logic.WallMode? = nil,
                   size newSize: Logic.BoardSize? = nil) {
        guard phase == .ready else { return }
        if let newSpeed {
            speed = newSpeed
            defaults.set(newSpeed.rawValue, forKey: Keys.speed)
        }
        let mode = newMode ?? state.wallMode
        let size = newSize ?? boardSize
        if mode != state.wallMode || size != boardSize {
            defaults.set(mode.rawValue, forKey: Keys.wallMode)
            defaults.set(size.rawValue, forKey: Keys.boardSize)
            state = .newGame(size: size, wallMode: mode)
            previousBody = state.body
            foodBorn = .now
        }
        bestAtStart = stats.stats(for: game, variant: statsVariant).bestScore ?? 0
        Feedback.play(.select)
    }

    func newGame(speed newSpeed: Logic.Speed? = nil, wallMode newMode: Logic.WallMode? = nil,
                 size newSize: Logic.BoardSize? = nil, autoStart: Bool) {
        stopTasks()
        if phase != .over && phase != .ready && (state.score > 0 || state.ticks > 0) {
            // Count an abandoned game that had progress.
            stats.record(game, variant: statsVariant, won: false, score: state.score, time: clock.elapsed())
        }
        if let newSpeed {
            speed = newSpeed
            defaults.set(newSpeed.rawValue, forKey: Keys.speed)
        }
        let mode = newMode ?? state.wallMode
        let size = newSize ?? boardSize
        defaults.set(mode.rawValue, forKey: Keys.wallMode)
        defaults.set(size.rawValue, forKey: Keys.boardSize)
        state = .newGame(size: size, wallMode: mode)
        previousBody = state.body
        frozenProgress = 1
        eatEvents = []
        deathDate = nil
        showGameOver = false
        clock = GameClock()
        foodBorn = .now
        bestAtStart = stats.stats(for: game, variant: statsVariant).bestScore ?? 0
        store.remove(key: game.saveKey)
        phase = .ready
        if autoStart { startCountdown() }
    }

    // MARK: Flow

    /// Starts a ready game or resumes a paused one (both after a 3-2-1 countdown).
    func play() {
        switch phase {
        case .ready, .paused: startCountdown()
        default: break
        }
    }

    func pause() {
        switch phase {
        case .running:
            frozenProgress = progress(at: .now)
        case .countdown:
            break
        default:
            return
        }
        stopTasks()
        phase = .paused
        clock.pause()
        Feedback.play(.tap)
        persist()
    }

    func togglePause() {
        if phase == .running || isCountingDown { pause() } else { play() }
    }

    var isCountingDown: Bool {
        if case .countdown = phase { return true }
        return false
    }

    func turn(_ direction: Direction) {
        switch phase {
        case .running, .countdown:
            state.turn(direction)
        case .ready:
            // Steering on a fresh board starts the game in that direction.
            state.turn(direction)
            startCountdown()
        default:
            break
        }
    }

    func setActive(_ active: Bool) {
        if !active {
            pause()
            persist()
        }
    }

    // MARK: Private

    private func startCountdown() {
        stopTasks()
        showGameOver = false
        countdownTask = Task { @MainActor [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.phase = .countdown(n)
                Feedback.play(.tap)
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard let self, !Task.isCancelled else { return }
            self.beginRunning()
        }
    }

    private func beginRunning() {
        phase = .running
        clock.start()
        // Continue the interrupted tick from where it was drawn.
        let remaining = (1 - frozenProgress) * speed.interval
        lastTick = Date.now.addingTimeInterval(-frozenProgress * speed.interval)
        Feedback.play(.select)
        runLoop(firstDelay: frozenProgress >= 1 ? speed.interval : remaining)
    }

    private func runLoop(firstDelay: Double) {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now + .seconds(firstDelay)
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: deadline, tolerance: .milliseconds(2))
                } catch {
                    return
                }
                guard let self, self.phase == .running else { return }
                self.step()
                guard self.phase == .running else { return }
                deadline += .seconds(self.speed.interval)
                // Don't try to catch up after a stall; just carry on.
                if deadline < clock.now { deadline = clock.now + .seconds(self.speed.interval) }
            }
        }
    }

    private func step() {
        previousBody = state.body
        let result = state.tick()
        lastTick = .now
        if result.ate {
            eatEvents.append(EatEvent(point: state.head, date: .now))
            if eatEvents.count > 6 { eatEvents.removeFirst() }
            foodBorn = .now
            Feedback.play(.eat)
            stats.submitScore(game, variant: statsVariant, score: state.score)
            AccessibilityNotification.Announcement("Score \(state.score)").post()
        }
        if result.died != nil || result.won {
            finish(won: result.won)
        }
    }

    private func finish(won: Bool) {
        stopTasks()
        // On death the snake stays where it was; show the final frame fully.
        if !won { previousBody = state.body }
        frozenProgress = 1
        phase = .over
        deathDate = won ? nil : .now
        clock.pause()
        stats.record(game, variant: statsVariant, won: won, score: state.score, time: clock.elapsed())
        store.remove(key: game.saveKey)
        Feedback.play(won ? .win : .lose)
        let message = won ? "You filled the board! Score \(state.score)." : "Game over. Score \(state.score)."
        AccessibilityNotification.Announcement(message).post()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(won ? 300 : 900))
            guard let self, self.phase == .over else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.showGameOver = true }
        }
    }

    private func stopTasks() {
        loop?.cancel()
        loop = nil
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func persist() {
        guard phase != .over, phase != .ready, state.ticks > 0 || state.score > 0 else { return }
        store.save(Saved(state: state, speed: speed, progress: frozenProgress,
                         previousBody: previousBody, clock: clock), key: game.saveKey)
    }
}
