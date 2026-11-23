import SwiftUI
import GameLogic

@MainActor @Observable
final class NonogramsPuzzleModel {
    typealias Logic = Nonograms

    let puzzle: Logic.Puzzle
    private(set) var board: Logic.Board
    private(set) var history: [Logic.Board] = []
    private(set) var clock = GameClock()
    private(set) var hintsUsed = 0
    private(set) var tool: Logic.Tool = .fill

    /// Whether the picture is complete (including a solved puzzle opened from the library).
    private(set) var isSolved = false
    /// True only when solved during this visit (drives the reveal animation and result card).
    private(set) var justSolved = false
    var showResult = false
    private(set) var isNewBest = false
    private(set) var finalTime: TimeInterval = 0

    /// The cell last touched, used to highlight its row and column.
    private(set) var focus: GridPoint?
    /// Cells briefly highlighted by Check.
    private(set) var flagged: Set<GridPoint> = []
    private(set) var checkMessage: String?
    /// Cell revealed by the latest hint.
    private(set) var hinted: GridPoint?
    /// The hint being explained; the board changes only when the player taps Show Answer.
    private(set) var hintPreview: Logic.Hint?

    private var stroke: Logic.Stroke?
    private var strokeBase: Logic.Board?
    private var strokeChanged: Set<GridPoint> = []
    private var flashTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    private let progress: NonogramsProgress
    private let stats: StatsStore
    private static let maxUndo = 100
    let game = GameID.nonograms

    init(puzzle: Logic.Puzzle, progress: NonogramsProgress = .shared, stats: StatsStore = .shared) {
        self.puzzle = puzzle
        self.progress = progress
        self.stats = stats
        let entry = progress.entry(puzzle)
        if let session = progress.session, session.puzzleID == puzzle.id {
            board = session.board
            history = session.history
            clock = session.clock
            hintsUsed = session.hintsUsed
            tool = session.tool
        } else if entry.solved && (entry.board == nil || entry.board?.isSolved(puzzle) == true) {
            board = .solved(puzzle)
            isSolved = true
        } else {
            board = entry.board ?? Logic.Board(for: puzzle)
            clock = GameClock(elapsed: entry.elapsed)
        }
    }

    // MARK: Derived

    var size: Logic.Size { puzzle.size ?? .easy }
    var number: Int { (Logic.puzzles(of: size).firstIndex(of: puzzle) ?? 0) + 1 }
    var canUndo: Bool { !history.isEmpty && !isSolved }
    var bestTime: TimeInterval? { progress.entry(puzzle).bestTime }

    func isRowDone(_ r: Int) -> Bool { board.isRowSatisfied(r, in: puzzle) }
    func isColumnDone(_ c: Int) -> Bool { board.isColumnSatisfied(c, in: puzzle) }

    static var statsVariants: [StatsVariant] {
        Logic.Size.allCases.map {
            StatsVariant(key: $0.rawValue, title: "\($0.title) · \($0.dimension)×\($0.dimension)", showsWins: false, showsTime: true)
        }
    }

    // MARK: Strokes

    func beginStroke(at p: GridPoint) {
        guard !isSolved, board.contains(p) else { return }
        clearTransientMarks()
        let s = Logic.Stroke(tool: tool, start: p, startingMark: board[p])
        stroke = s
        strokeBase = board
        strokeChanged = []
        focus = p
        continueStroke(to: p)
    }

    func continueStroke(to p: GridPoint) {
        guard let stroke, let base = strokeBase else { return }
        var next = base
        let changed = next.apply(stroke, to: p)
        let end = stroke.cells(to: p).last ?? p
        if focus != end { focus = end }
        guard next != board else { return }
        let fresh = changed.filter { !strokeChanged.contains($0) }
        board = next
        if !fresh.isEmpty {
            if strokeChanged.isEmpty { Feedback.play(.tap) } else { Haptics.select() }
            strokeChanged.formUnion(fresh)
        }
    }

    func endStroke() {
        guard let base = strokeBase else { return }
        stroke = nil
        strokeBase = nil
        guard base != board else { return }
        clock.start()
        history.append(base)
        if history.count > Self.maxUndo { history.removeFirst() }
        afterChange(from: base)
    }

    /// Applies the current tool to one cell (VoiceOver and keyboard-free access).
    func apply(_ mark: Logic.Mark, at p: GridPoint) {
        guard !isSolved, board.contains(p) else { return }
        let toolForMark: Logic.Tool = mark == .crossed ? .cross : .fill
        let current = board[p]
        let base = board
        var next = board
        if mark == .empty {
            guard current != .empty else { return }
            next.apply(Logic.Stroke(tool: current == .filled ? .fill : .cross, start: p, startingMark: current), to: p)
        } else {
            guard current != mark else { return }
            next.apply(Logic.Stroke(tool: toolForMark, start: p, startingMark: current), to: p)
        }
        focus = p
        board = next
        clock.start()
        history.append(base)
        Feedback.play(.tap)
        afterChange(from: base)
    }

    // MARK: Tools

    func setTool(_ newTool: Logic.Tool) {
        guard newTool != tool else { return }
        dismissHint()
        tool = newTool
        persist()
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        clearTransientMarks()
        board = previous
        Feedback.play(.flip)
        persist()
    }

    /// Explains the next step: highlights the deciding row or column and its square. The mark
    /// is written only when the player asks for it (`showHintAnswer`).
    func hint() {
        guard !isSolved, hintPreview == nil, let hint = board.explainedHint(for: puzzle) else { return }
        clearTransientMarks()
        hintsUsed += 1
        hinted = hint.point
        focus = hint.point
        hintPreview = hint
        clock.start()
        Feedback.play(.select)
        persist()
    }

    /// Writes the explained hint's mark.
    func showHintAnswer() {
        guard !isSolved, let hint = hintPreview else { return }
        hintPreview = nil
        let base = board
        board[hint.point] = hint.mark
        history.append(base)
        hinted = hint.point
        focus = hint.point
        Feedback.play(.pop)
        afterChange(from: base)
    }

    /// Whether a row is highlighted: the focused square's row, or only the hint's deciding line.
    func highlightsRow(_ r: Int) -> Bool {
        if let hint = hintPreview { return hint.line.map { $0 == .row(r) } ?? (hint.point.row == r) }
        return focus?.row == r
    }

    func highlightsColumn(_ c: Int) -> Bool {
        if let hint = hintPreview { return hint.line.map { $0 == .column(c) } ?? (hint.point.col == c) }
        return focus?.col == c
    }

    func dismissHint() {
        guard hintPreview != nil else { return }
        hintPreview = nil
        hinted = nil
    }

    /// Briefly highlights mistakes, or confirms there are none.
    func check() {
        guard !isSolved else { return }
        clearTransientMarks()
        let mistakes = board.mistakes(in: puzzle)
        if mistakes.isEmpty {
            checkMessage = board.isBlank ? "Start by filling cells you're sure about." : "No mistakes so far — keep going!"
            Feedback.play(.select)
        } else {
            flagged = Set(mistakes)
            checkMessage = mistakes.count == 1 ? "1 cell doesn't match the picture." : "\(mistakes.count) cells don't match the picture."
            Feedback.play(.invalid)
        }
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.flagged = []
                self.checkMessage = nil
            }
        }
    }

    func restart() {
        clearTransientMarks()
        resultTask?.cancel()
        board = Logic.Board(for: puzzle)
        history = []
        clock = GameClock()
        hintsUsed = 0
        isSolved = false
        justSolved = false
        showResult = false
        focus = nil
        progress.update(puzzle) { $0.board = nil; $0.elapsed = 0 }
        progress.clearSession()
    }

    func setActive(_ active: Bool) {
        if active, !isSolved, !board.isBlank { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Internals

    private func clearTransientMarks() {
        flashTask?.cancel()
        if !flagged.isEmpty || checkMessage != nil {
            flagged = []
            checkMessage = nil
        }
        hinted = nil
        hintPreview = nil
    }

    private func afterChange(from base: Logic.Board) {
        if board.isSolved(puzzle) {
            solve()
            return
        }
        // A satisfying chime when a stroke completes a row or column.
        let rows = (0..<puzzle.height).filter { board.isRowSatisfied($0, in: puzzle) && !base.isRowSatisfied($0, in: puzzle) }
        let cols = (0..<puzzle.width).filter { board.isColumnSatisfied($0, in: puzzle) && !base.isColumnSatisfied($0, in: puzzle) }
        if !rows.isEmpty || !cols.isEmpty { Feedback.play(.merge) }
        persist()
    }

    private func solve() {
        clock.pause()
        finalTime = clock.elapsed()
        isSolved = true
        justSolved = true
        focus = nil
        hinted = nil
        flagged = []
        checkMessage = nil
        // Clean up stray crosses so the picture reads clearly.
        board = .solved(puzzle)
        let previousBest = progress.entry(puzzle).bestTime
        isNewBest = previousBest.map { finalTime < $0 } ?? true
        progress.update(puzzle) {
            $0.solved = true
            $0.board = nil
            $0.elapsed = 0
            $0.timesSolved += 1
            $0.bestTime = min($0.bestTime ?? .infinity, finalTime)
        }
        progress.clearSession()
        stats.record(game, variant: size.rawValue, won: true, time: finalTime)
        Feedback.play(.win)
        resultTask?.cancel()
        resultTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled, self.isSolved else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.showResult = true }
        }
    }

    private func persist() {
        guard !isSolved else { return }
        let elapsed = clock.elapsed()
        progress.update(puzzle) {
            $0.board = board.isBlank ? nil : board
            $0.elapsed = elapsed
        }
        if board.isBlank && history.isEmpty {
            progress.clearSession()
        } else {
            progress.saveSession(.init(puzzleID: puzzle.id, board: board, history: history, clock: clock,
                                       hintsUsed: hintsUsed, tool: tool))
        }
    }
}

private extension GameClock {
    /// A paused clock that has already accumulated `elapsed` seconds.
    init(elapsed: TimeInterval) {
        self.init()
        guard elapsed > 0 else { return }
        let start = Date.now
        self.start(at: start.addingTimeInterval(-elapsed))
        self.pause(at: start)
    }
}
