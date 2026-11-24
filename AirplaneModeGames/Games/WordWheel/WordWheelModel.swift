import SwiftUI
import GameLogic

@MainActor @Observable
final class WordWheelModel {
    typealias Logic = WordWheel

    /// Feedback shown above the current word after Enter.
    struct Message: Equatable {
        enum Kind { case good, bonus, pangram, rank, problem }
        let text: String
        let kind: Kind
        let token: Int
    }

    private struct Saved: Codable {
        var state: Logic.State
        var clock: GameClock
        /// Daily: the solve (reaching Great) was already recorded.
        var solvedRecorded: Bool
        /// Optional so saves from before hints existed still load.
        var clue: Logic.Clue?
        var hintsUsed: Int?
    }

    private(set) var state: Logic.State?
    private(set) var isLoading = false
    private(set) var clock = GameClock()
    private(set) var message: Message?
    private(set) var shakeToken = 0
    private(set) var pangramToken = 0
    /// Bumped when a letter is typed, keyed by letter, so its tile can pulse.
    private(set) var tapTokens: [String: Int] = [:]
    /// Cumulative clockwise angle (degrees) of each ring letter; shuffles only ever add to it, so
    /// tiles travel around the ring instead of cutting across it.
    private(set) var ringAngles: [String: Double] = [:]
    private(set) var lastFound: String?
    private(set) var showResult = false
    private(set) var celebrating = false
    /// Daily: today's solve has been recorded (now, or on an earlier visit).
    private(set) var solvedRecorded = false
    /// Daily: shows the "solved" banner right after reaching Great.
    private(set) var justSolvedDaily = false
    /// The current clue for an unfound answer, and whether its panel is showing.
    private(set) var clue: Logic.Clue?
    private(set) var showClue = false
    /// Clues revealed on this wheel (shown with the result).
    private(set) var hintsUsed = 0

    private let store: GameStore
    private let stats: StatsStore
    private var dictionary: Logic.Dictionary?
    private var messageToken = 0
    private var generation = 0
    private var isActive = false
    let game = GameID.wordWheel

    /// Today, when this is the daily wheel (letters fixed by the date, saved separately).
    let daily: Daily.Day?
    private var saveKey: String { daily.map { game.dailySaveKey($0) } ?? game.saveKey }

    init(daily: Daily.Day? = nil, store: GameStore = .shared, stats: StatsStore = .shared) {
        self.daily = daily
        self.store = store
        self.stats = stats
        let key = daily.map { GameID.wordWheel.dailySaveKey($0) } ?? GameID.wordWheel.saveKey
        if let saved = store.load(Saved.self, key: key), !saved.state.isFinished {
            adopt(saved.state)
            clock = saved.clock
            solvedRecorded = saved.solvedRecorded
            clue = saved.clue
            hintsUsed = saved.hintsUsed ?? 0
        }
    }

    // MARK: Derived

    var puzzle: Logic.Puzzle? { state?.puzzle }
    var score: Int { state?.score ?? 0 }
    var rank: Logic.Rank { state?.rank ?? .starter }
    var maxPoints: Int { puzzle?.maxPoints ?? 0 }
    var foundAnswerCount: Int { state?.foundAnswers.count ?? 0 }
    var answerCount: Int { puzzle?.answers.count ?? 0 }
    var isFinished: Bool { state?.isFinished == true }
    var canPlay: Bool { state.map { !$0.isFinished } ?? false }
    var bestScore: Int? { stats.stats(for: game).bestScore }

    func points(toReach rank: Logic.Rank) -> Int { puzzle?.threshold(rank) ?? 0 }

    // MARK: Lifecycle

    /// Builds the first wheel and warms the word list, off the main actor. Call from the view.
    func prepare() async {
        #if DEBUG
        if state == nil, Self.debugScenario {
            let dictionary = await Self.loadDictionary()
            self.dictionary = dictionary
            adopt(Logic.State(puzzle: Logic.puzzle(center: "a", outer: Array("einprt"), dictionary: dictionary)))
            runDemoIfRequested()
            if isActive { clock.start() }
            return
        }
        #endif
        if state == nil {
            await generate()
        } else if dictionary == nil {
            dictionary = await Self.loadDictionary()
        }
        if let daily, DailyStore.shared.isDone(game, on: daily) { solvedRecorded = true }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active, canPlay { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Input

    func type(_ letter: Character) {
        guard var s = state, s.type(letter) else { return }
        state = s
        let key = String(letter).lowercased()
        tapTokens[key, default: 0] += 1
        Feedback.play(.tap)
    }

    func deleteLetter() {
        guard var s = state, s.deleteLetter() else { return }
        state = s
        Haptics.tap()
    }

    func clearInput() {
        guard var s = state, !s.input.isEmpty else { return }
        s.clearInput()
        state = s
        Haptics.tap()
    }

    func shuffle() {
        guard var s = state, canPlay else { return }
        let before = s.ring
        var rng = SystemRandomNumberGenerator()
        s.shuffle(using: &rng)
        state = s
        for (newIndex, letter) in s.ring.enumerated() {
            let oldIndex = before.firstIndex(of: letter) ?? newIndex
            let steps = ((newIndex - oldIndex) % 6 + 6) % 6
            ringAngles[letter, default: Double(oldIndex) * 60] += Double(steps == 0 ? 6 : steps) * 60
        }
        Feedback.play(.flip)
        persist()
    }

    func submit() {
        guard var s = state, canPlay, !s.input.isEmpty else { return }
        let dictionary = self.dictionary ?? Logic.Dictionary.bundled
        self.dictionary = dictionary
        let result = s.submit(isValidWord: dictionary.isValid)
        state = s
        switch result {
        case .failure(let rejection):
            shakeToken += 1
            Feedback.play(.invalid)
            show(rejection.message, kind: .problem)
        case .success(let accepted):
            accept(accepted)
        }
    }

    private func accept(_ a: Logic.Accepted) {
        if a.word == clue?.word {
            withAnimation(.snappy(duration: 0.25)) {
                clue = nil
                showClue = false
            }
        }
        withAnimation(.snappy(duration: 0.25)) { lastFound = a.word }
        if a.isPangram {
            pangramToken += 1
            Feedback.play(.win)
            show("Pangram! +\(a.points)", kind: .pangram, duration: 2.2)
            celebrate()
        } else if a.rankedUp {
            Feedback.play(.clear)
            show("\(a.rankAfter.title)! +\(a.points)", kind: .rank, duration: 1.8)
        } else if !a.isAnswer {
            Feedback.play(.merge)
            show("Bonus word! +\(a.points)", kind: .bonus)
        } else {
            Feedback.play(.merge)
            show("\(Self.praise(a.word)) +\(a.points)", kind: .good)
        }
        if a.rankedUp && a.isPangram {
            AccessibilityNotification.Announcement("Rank: \(a.rankAfter.title)").post()
        }
        if a.rankedUp, a.rankAfter >= Logic.Rank.solved { recordDailySolveIfNeeded() }
        if state?.foundAllAnswers == true {
            show("Every answer found!", kind: .rank, duration: 2.4)
            celebrate()
        }
        persist()
    }

    static func praise(_ word: String) -> String {
        switch word.count {
        case ...4: "Good"
        case 5: "Nice"
        case 6: "Lovely"
        default: "Superb"
        }
    }

    private func recordDailySolveIfNeeded() {
        guard let daily, !solvedRecorded else { return }
        solvedRecorded = true
        // Recording clears the daily save; `persist()` right after saves it again so play can go on.
        DailyStore.shared.record(game, on: daily, won: true, time: clock.elapsed())
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { justSolvedDaily = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.3)) { self?.justSolvedDaily = false }
        }
    }

    private func celebrate() {
        celebrating = true
        let token = pangramToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.pangramToken == token else { return }
            self.celebrating = false
        }
    }

    private func show(_ text: String, kind: Message.Kind, duration: Double = 1.4) {
        messageToken += 1
        let token = messageToken
        withAnimation(.snappy(duration: 0.2)) { message = Message(text: text, kind: kind, token: token) }
        AccessibilityNotification.Announcement(text).post()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.messageToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.message = nil }
        }
    }

    // MARK: Hints

    /// Answers not found yet, by length (for the clue panel).
    var answersLeftByLength: [Logic.LengthCount] { state?.answersLeftByLength ?? [] }

    /// Shows the clue panel again if it was closed; otherwise reveals more of the current clue,
    /// or starts a clue for another unfound answer once this one is fully shown.
    /// Hinted words score like any other: the clue only narrows the search.
    func hint() {
        guard let s = state, canPlay else { return }
        if let clue, !showClue, s.missedAnswers.contains(clue.word) {
            withAnimation(.snappy(duration: 0.25)) { showClue = true }
            Feedback.play(.select)
            announce(clue)
            return
        }
        var rng = SystemRandomNumberGenerator()
        guard let next = s.nextClue(after: clue, using: &rng) else {
            show("Every answer found!", kind: .rank)
            return
        }
        hintsUsed += 1
        withAnimation(.snappy(duration: 0.25)) {
            clue = next
            showClue = true
        }
        Feedback.play(.select)
        announce(next)
        persist()
    }

    func closeClue() {
        withAnimation(.snappy(duration: 0.25)) { showClue = false }
    }

    private func announce(_ clue: Logic.Clue) {
        AccessibilityNotification.Announcement("\(clue.title). \(clue.spokenPattern)").post()
    }

    // MARK: Finish

    /// Ends the wheel, reveals the missed answers and records the result.
    func finish() {
        guard var s = state, canPlay else { return }
        s.finish()
        state = s
        clock.pause()
        showClue = false
        let won = s.rank >= Logic.Rank.solved
        if let daily {
            if !solvedRecorded {
                DailyStore.shared.record(game, on: daily, won: false, time: nil)
                solvedRecorded = true
            }
        } else {
            stats.record(game, won: won, score: s.score, time: clock.elapsed())
        }
        store.remove(key: saveKey)
        Feedback.play(won ? .win : .place)
        withAnimation { showResult = true }
    }

    func dismissResult() { withAnimation { showResult = false } }
    func reopenResult() { withAnimation { showResult = true } }

    // MARK: New wheels

    /// A new random wheel (abandoning one with progress counts it in the stats).
    func newGame() {
        guard daily == nil else { return }
        if let s = state, !s.isFinished, s.hasProgress {
            stats.record(game, won: s.rank >= Logic.Rank.solved, score: s.score, time: clock.elapsed())
        }
        store.remove(key: saveKey)
        Task { await generate() }
    }

    private func generate() async {
        generation += 1
        let token = generation
        let seed = daily.map { game.dailySeed($0) }
        isLoading = true
        let (puzzle, dictionary) = await Self.makePuzzle(seed: seed)
        guard generation == token else { return }
        self.dictionary = dictionary
        withAnimation(.easeOut(duration: 0.25)) {
            adopt(Logic.State(puzzle: puzzle))
            isLoading = false
        }
        clock = GameClock()
        if isActive { clock.start() }
    }

    private func adopt(_ newState: Logic.State) {
        state = newState
        ringAngles = Dictionary(uniqueKeysWithValues: newState.ring.enumerated().map { ($1, Double($0) * 60) })
        message = nil
        lastFound = nil
        showResult = false
        celebrating = false
        justSolvedDaily = false
        tapTokens = [:]
        clue = nil
        showClue = false
        hintsUsed = 0
        if daily == nil { solvedRecorded = false }
    }

    nonisolated private static func makePuzzle(seed: UInt64?) async -> (Logic.Puzzle, Logic.Dictionary) {
        await Task.detached(priority: .userInitiated) {
            var rng = seed.map { SeededRandom(seed: $0) } ?? SeededRandom()
            let dictionary = Logic.Dictionary.bundled
            return (Logic.generate(using: &rng, dictionary: dictionary), dictionary)
        }.value
    }

    nonisolated private static func loadDictionary() async -> Logic.Dictionary {
        await Task.detached(priority: .userInitiated) { Logic.Dictionary.bundled }.value
    }

    #if DEBUG
    /// `-wordWheelScenario fixed`: center A, ring E I N P R T (for UI tests and screenshots);
    /// `demo` also enters a few words.
    private static var debugScenario: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wordWheelScenario"), i + 1 < args.count else { return false }
        return ["fixed", "demo"].contains(args[i + 1])
    }

    /// `-wordWheelScenario demo` enters some words for screenshots.
    private func runDemoIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wordWheelScenario"), i + 1 < args.count, args[i + 1] == "demo",
              var s = state, s.found.isEmpty, let dictionary else { return }
        for word in ["paint", "train", "parent", "pirate", "retain", "tarp", "pain", "pear", "painter", "near", "rant"] {
            _ = s.enter(word, isValidWord: dictionary.isValid)
        }
        for ch in "pre" { s.type(ch) }
        state = s
        lastFound = "painter"
    }
    #endif

    // MARK: Persistence

    private func persist() {
        guard let s = state else { return }
        if s.isFinished || (!s.hasProgress && hintsUsed == 0) {
            store.remove(key: saveKey)
        } else {
            store.save(Saved(state: s, clock: clock, solvedRecorded: solvedRecorded, clue: clue, hintsUsed: hintsUsed),
                       key: saveKey)
        }
    }
}
