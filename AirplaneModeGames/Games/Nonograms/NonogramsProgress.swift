import SwiftUI
import GameLogic

/// Per-puzzle progress (boards in progress, solved state, best times), persisted locally.
@MainActor @Observable
final class NonogramsProgress {
    struct Entry: Codable, Equatable {
        var board: Nonograms.Board?
        var elapsed: TimeInterval = 0
        var solved = false
        var bestTime: TimeInterval?
        var timesSolved = 0
    }

    /// The puzzle currently being played, including its undo history.
    struct Session: Codable {
        var puzzleID: String
        var board: Nonograms.Board
        var history: [Nonograms.Board]
        var clock: GameClock
        var hintsUsed: Int
        var tool: Nonograms.Tool
    }

    static let shared = NonogramsProgress()

    private(set) var entries: [String: Entry]
    private let store: GameStore
    private static let key = "nonograms.progress"
    let game = GameID.nonograms

    init(store: GameStore = .shared) {
        self.store = store
        entries = store.load([String: Entry].self, key: Self.key) ?? [:]
    }

    func entry(_ puzzle: Nonograms.Puzzle) -> Entry { entries[puzzle.id] ?? Entry() }

    func isSolved(_ puzzle: Nonograms.Puzzle) -> Bool { entry(puzzle).solved }

    func isStarted(_ puzzle: Nonograms.Puzzle) -> Bool {
        guard let board = entry(puzzle).board else { return false }
        return !board.isBlank
    }

    func solvedCount(_ size: Nonograms.Size? = nil) -> Int {
        Nonograms.library.filter { (size == nil || $0.size == size) && isSolved($0) }.count
    }

    /// The first unsolved puzzle of a size (or the first puzzle if all are solved).
    func nextPuzzle(of size: Nonograms.Size, after current: Nonograms.Puzzle? = nil) -> Nonograms.Puzzle? {
        let all = Nonograms.puzzles(of: size)
        let start = current.flatMap { c in all.firstIndex(of: c).map { $0 + 1 } } ?? 0
        let rotated = Array(all[min(start, all.count)...] + all[..<min(start, all.count)])
        return rotated.first { !isSolved($0) && $0 != current } ?? rotated.first { $0 != current } ?? all.first
    }

    func update(_ puzzle: Nonograms.Puzzle, _ change: (inout Entry) -> Void) {
        var e = entry(puzzle)
        change(&e)
        entries[puzzle.id] = e
        store.save(entries, key: Self.key)
    }

    // MARK: Session

    var session: Session? { store.load(Session.self, key: game.saveKey) }

    func saveSession(_ session: Session) { store.save(session, key: game.saveKey) }

    func clearSession() { store.remove(key: game.saveKey) }
}
