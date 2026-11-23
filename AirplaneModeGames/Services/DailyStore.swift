import Foundation
import GameLogic
import Observation

extension GameID {
    /// Games with a daily puzzle: ones where a fixed puzzle of the day makes sense.
    static let withDaily: [GameID] = [.sudoku, .wordGuess, .solitaire, .minesweeper, .wordSearch, .tileMatch]

    var hasDaily: Bool { Self.withDaily.contains(self) }

    /// Where today's daily puzzle in progress is saved (separate from the regular game).
    func dailySaveKey(_ day: Daily.Day) -> String { "daily.\(rawValue).\(day.key)" }

    /// The seed of this game's puzzle on `day`.
    func dailySeed(_ day: Daily.Day) -> UInt64 { Daily.seed(day: day, game: rawValue) }
}

/// Which days each game's daily puzzle was finished, and how. Streaks count won days.
@MainActor @Observable
final class DailyStore {
    struct Entry: Codable, Equatable {
        var won: Bool
        var time: TimeInterval?
    }

    static let shared = DailyStore()

    /// game raw value → day key → result.
    private(set) var entries: [String: [String: Entry]]
    private let store: GameStore
    private static let key = "daily.records"

    init(store: GameStore = .shared) {
        self.store = store
        entries = store.load([String: [String: Entry]].self, key: Self.key) ?? [:]
    }

    var today: Daily.Day { Daily.Day() }

    func entry(_ game: GameID, on day: Daily.Day) -> Entry? { entries[game.rawValue]?[day.key] }

    /// Played to the end today (won, or lost for good).
    func isDone(_ game: GameID, on day: Daily.Day) -> Bool { entry(game, on: day) != nil }

    func wonDays(_ game: GameID) -> Set<Daily.Day> {
        Set((entries[game.rawValue] ?? [:]).compactMap { $0.value.won ? Daily.Day(key: $0.key) : nil })
    }

    func streak(_ game: GameID) -> Int { Daily.streak(won: wonDays(game), today: today) }
    func bestStreak(_ game: GameID) -> Int { Daily.bestStreak(won: wonDays(game)) }
    func playedCount(_ game: GameID) -> Int { entries[game.rawValue]?.count ?? 0 }
    func wonCount(_ game: GameID) -> Int { entries[game.rawValue]?.values.filter(\.won).count ?? 0 }

    /// Records the first finish of `day`'s puzzle (replays don't change it) and clears its save.
    func record(_ game: GameID, on day: Daily.Day, won: Bool, time: TimeInterval?) {
        store.remove(key: game.dailySaveKey(day))
        guard entry(game, on: day) == nil else { return }
        entries[game.rawValue, default: [:]][day.key] = Entry(won: won, time: time)
        store.save(entries, key: Self.key)
        if won { StatsStore.shared.record(game, variant: StatsVariant.dailyKey, won: true, time: time) }
    }

    /// Drops saves of earlier days' unfinished dailies (they can't be finished any more).
    func clearOldSaves(_ game: GameID, before day: Daily.Day) {
        var d = day.previous
        for _ in 0..<14 {
            store.remove(key: game.dailySaveKey(d))
            d = d.previous
        }
    }

    func reset() {
        entries = [:]
        store.remove(key: Self.key)
    }
}
