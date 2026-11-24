import SwiftUI
import GameLogic

@MainActor @Observable
final class BlockPuzzleModel {
    typealias Logic = BlockPuzzle

    /// Cells removed by a clear, still on screen while they pop.
    struct Burst: Identifiable {
        let id = UUID()
        let cells: [Logic.ClearedCell]
        /// Where the stagger radiates from (board coordinates, in cells).
        let center: CGPoint
    }

    /// Floating "+score" / "Combo" text.
    struct Floater: Identifiable {
        let id = UUID()
        let points: Int
        let caption: String?
        let color: Int
        /// Board coordinates, in cells.
        let center: CGPoint
    }

    private struct Saved: Codable {
        var state: Logic.State
        var undoState: Logic.State?
        var undosLeft: Int
        var bestAtStart: Int
        var clock: GameClock
    }

    static let undosPerGame = 3

    private(set) var state: Logic.State
    /// The state before the latest placement (one step of undo).
    private(set) var undoState: Logic.State?
    private(set) var undosLeft = BlockPuzzleModel.undosPerGame
    private(set) var clock = GameClock()
    private(set) var isOver = false
    /// Shown a moment after the game ends so the last move can finish animating.
    private(set) var showGameOver = false
    private(set) var bursts: [Burst] = []
    private(set) var floaters: [Floater] = []
    /// Cells filled by the latest placement and a token that bumps each placement (for bounce).
    private(set) var lastPlaced: Set<GridPoint> = []
    private(set) var placementToken = 0
    /// Tray slot picked with a tap (tap-to-place / VoiceOver mode).
    var selectedSlot: Int?
    /// Best score before this game started, to detect a new record.
    private(set) var bestAtStart: Int
    /// A suggested placement, shown as a ghost on the board for a few seconds.
    private(set) var hint: Logic.Advisor.Suggestion?
    /// A hint is being worked out.
    private(set) var isThinking = false
    private var hintToken = 0

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.blocks

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        let best = stats.stats(for: .blocks).bestScore ?? 0
        if let saved = store.load(Saved.self, key: GameID.blocks.saveKey), !saved.state.isOver {
            state = saved.state
            undoState = saved.undoState
            undosLeft = saved.undosLeft
            bestAtStart = saved.bestAtStart
            clock = saved.clock
        } else {
            state = .newGame()
            bestAtStart = best
        }
    }

    var best: Int { max(stats.stats(for: game).bestScore ?? 0, state.score) }
    /// Beat a previous record (a first-ever game doesn't count as a "new best").
    var isNewBest: Bool { bestAtStart > 0 && state.score > bestAtStart }
    var canUndo: Bool { undoState != nil && undosLeft > 0 && !isOver }

    func piece(in slot: Int) -> Logic.Piece? {
        state.tray.indices.contains(slot) ? state.tray[slot] : nil
    }

    // MARK: Actions

    /// Places the piece in `slot` at `origin`. Returns `false` if it doesn't fit.
    @discardableResult
    func place(slot: Int, at origin: GridPoint) -> Bool {
        guard !isOver else { return false }
        let previous = state
        guard let result = state.place(slot: slot, at: origin) else {
            Feedback.play(.invalid)
            return false
        }
        undoState = previous
        selectedSlot = nil
        clearHint()
        clock.start()
        lastPlaced = Set(result.placedCells)
        placementToken += 1

        if result.lineCount > 0 {
            celebrate(result)
        } else {
            Feedback.play(.place)
        }
        stats.submitScore(game, score: state.score)

        if state.isOver { finish() }
        persist()
        return true
    }

    /// Tap-to-place: centers the selected piece on `cell`, snapping to the closest spot that fits.
    func tapCell(_ cell: GridPoint) {
        guard let slot = selectedSlot, let piece = piece(in: slot) else {
            Haptics.tap()
            return
        }
        let origin = piece.origin(centeredOn: cell)
        if state.board.fits(piece, at: origin) {
            place(slot: slot, at: origin)
        } else if let snapped = state.board.nearestValidOrigin(for: piece, row: Double(origin.row),
                                                               col: Double(origin.col), maxDistance: 1.5) {
            place(slot: slot, at: snapped)
        } else {
            Feedback.play(.invalid)
            AccessibilityNotification.Announcement("Doesn't fit there").post()
        }
    }

    func select(slot: Int) {
        guard !isOver, piece(in: slot) != nil else { return }
        selectedSlot = selectedSlot == slot ? nil : slot
        Feedback.play(.select)
    }

    func undo() {
        guard canUndo, let previous = undoState else { return }
        state = previous
        undoState = nil
        undosLeft -= 1
        clearHint()
        selectedSlot = nil
        bursts = []
        floaters = []
        lastPlaced = []
        placementToken += 1
        Feedback.play(.flip)
        persist()
    }

    func newGame() {
        if state.piecesPlaced > 0 && !isOver {
            // Count an abandoned game that had progress.
            stats.record(game, won: false, score: state.score, time: clock.elapsed())
        }
        clearHint()
        state = .newGame()
        undoState = nil
        undosLeft = Self.undosPerGame
        bestAtStart = stats.stats(for: game).bestScore ?? 0
        isOver = false
        showGameOver = false
        bursts = []
        floaters = []
        lastPlaced = []
        selectedSlot = nil
        placementToken += 1
        clock = GameClock()
        store.remove(key: game.saveKey)
    }

    /// Finds a good placement off the main actor and shows it as a ghost for a few seconds.
    /// Hints are free and leave the score alone.
    func showHint() {
        guard !isOver, !isThinking else { return }
        hintToken += 1
        let token = hintToken
        let position = state
        isThinking = true
        Task { @MainActor [weak self] in
            let suggestion = await Task.detached(priority: .userInitiated) {
                Logic.Advisor.suggestion(for: position)
            }.value
            guard let self, self.hintToken == token else { return }
            self.isThinking = false
            guard let suggestion, let piece = self.piece(in: suggestion.slot) else {
                Feedback.play(.invalid)
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { self.hint = suggestion }
            Feedback.play(.select)
            AccessibilityNotification.Announcement(Self.describe(suggestion, piece: piece)).post()
            try? await Task.sleep(for: Self.hintDuration)
            guard self.hintToken == token else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.hint = nil }
        }
    }

    /// "Try the L piece at row 3, column 5. It clears a line."
    static func describe(_ hint: Logic.Advisor.Suggestion, piece: Logic.Piece) -> String {
        var name = BlockPuzzleView.describe(piece).components(separatedBy: ",").first ?? "piece"
        // "Single block" reads "single block"; letter names like "L piece" keep their capital.
        if name.dropFirst().first != " " { name = name.prefix(1).lowercased() + name.dropFirst() }
        var text = "Try the \(name) with its top-left corner at row \(hint.origin.row + 1), column \(hint.origin.col + 1)."
        if hint.lines > 0 { text += hint.lines == 1 ? " It clears a line." : " It clears \(hint.lines) lines." }
        return text
    }

    /// How long a hint stays up (DEBUG `-hintDemo` keeps it for screenshots).
    private static var hintDuration: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hintDemo") { return .seconds(600) }
        #endif
        return .seconds(4)
    }

    private func clearHint() {
        hintToken += 1
        hint = nil
        isThinking = false
    }

    func setActive(_ active: Bool) {
        if active, !isOver, state.piecesPlaced > 0 { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Private

    private func celebrate(_ result: Logic.Placement) {
        let cells = result.clearedCells
        let cx = cells.map { CGFloat($0.point.col) + 0.5 }.reduce(0, +) / CGFloat(max(cells.count, 1))
        let cy = cells.map { CGFloat($0.point.row) + 0.5 }.reduce(0, +) / CGFloat(max(cells.count, 1))
        let pieceCenter = CGPoint(
            x: CGFloat(result.origin.col) + CGFloat(result.piece.width) / 2,
            y: CGFloat(result.origin.row) + CGFloat(result.piece.height) / 2)
        let burst = Burst(cells: cells, center: pieceCenter)
        bursts.append(burst)

        var caption: String?
        if result.isPerfectClear {
            caption = "Perfect Clear!"
        } else if result.lineCount >= 2 {
            caption = "Combo ×\(result.lineCount)!"
        } else if result.streak >= 2 {
            caption = "Streak ×\(result.streak)"
        }
        let floater = Floater(points: result.points, caption: caption, color: result.piece.color,
                              center: CGPoint(x: min(max(cx, 2), 6), y: min(max(cy, 1.2), 6.8)))
        floaters.append(floater)

        Feedback.play(result.isPerfectClear || result.lineCount >= 3 ? .win : .clear)
        var announcement = "Cleared \(result.lineCount) \(result.lineCount == 1 ? "line" : "lines"), plus \(result.points)."
        if let caption { announcement = caption + " " + announcement }
        AccessibilityNotification.Announcement(announcement).post()

        let burstID = burst.id, floaterID = floater.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.bursts.removeAll { $0.id == burstID }
            try? await Task.sleep(for: .milliseconds(500))
            self?.floaters.removeAll { $0.id == floaterID }
        }
    }

    private func finish() {
        isOver = true
        selectedSlot = nil
        clock.pause()
        stats.record(game, won: false, score: state.score, time: clock.elapsed())
        let token = placementToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard let self, self.isOver, self.placementToken == token else { return }
            Feedback.play(self.isNewBest ? .win : .lose)
            withAnimation(.easeOut(duration: 0.25)) { self.showGameOver = true }
        }
    }

    private func persist() {
        if isOver {
            store.remove(key: game.saveKey)
        } else if state.piecesPlaced > 0 {
            store.save(Saved(state: state, undoState: undoState, undosLeft: undosLeft,
                             bestAtStart: bestAtStart, clock: clock), key: game.saveKey)
        } else {
            store.remove(key: game.saveKey)
        }
    }
}
