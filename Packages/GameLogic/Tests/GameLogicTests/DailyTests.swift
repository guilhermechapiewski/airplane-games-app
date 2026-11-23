import Foundation
import Testing
@testable import GameLogic

@Suite("Daily puzzles")
struct DailyTests {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s + "T12:00:00Z")!
    }

    @Test func dayKeyUsesTheLocalCalendarDay() {
        #expect(Daily.Day(date("2026-11-22"), calendar: utc).key == "2026-11-22")
        #expect(Daily.Day(key: "2026-03-05")?.key == "2026-03-05")
        #expect(Daily.Day(key: "nope") == nil)
    }

    @Test func seedsAreStableAndDifferPerGameAndDay() {
        let day = Daily.Day(key: "2026-11-22")!
        // Stable across runs and devices (FNV-1a, not Swift's per-process Hasher).
        #expect(Daily.seed(day: day, game: "sudoku") == Daily.seed(day: day, game: "sudoku"))
        #expect(Daily.seed(day: day, game: "sudoku") != Daily.seed(day: day, game: "wordGuess"))
        #expect(Daily.seed(day: day, game: "sudoku") != Daily.seed(day: day.next, game: "sudoku"))
    }

    @Test func seedIsAFixedValue() {
        // Pinned so an accidental change to the hash (which would change everyone's puzzle) fails.
        let day = Daily.Day(key: "2026-11-22")!
        #expect(Daily.seed(day: day, game: "sudoku") == Daily.fnv1a("2026-11-22|sudoku"))
        #expect(Daily.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(Daily.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func dayArithmetic() {
        let d = Daily.Day(key: "2026-02-28")!
        #expect(d.next.key == "2026-03-01")
        #expect(d.previous.key == "2026-02-27")
        #expect(Daily.Day(key: "2026-01-01")!.previous.key == "2025-12-31")
    }

    @Test func streakCountsConsecutiveWonDaysEndingTodayOrYesterday() {
        let today = Daily.Day(key: "2026-11-22")!
        func days(_ keys: [String]) -> Set<Daily.Day> { Set(keys.compactMap(Daily.Day.init(key:))) }
        #expect(Daily.streak(won: days([]), today: today) == 0)
        #expect(Daily.streak(won: days(["2026-11-22"]), today: today) == 1)
        #expect(Daily.streak(won: days(["2026-11-20", "2026-11-21", "2026-11-22"]), today: today) == 3)
        // Today not played yet: yesterday's streak is still alive.
        #expect(Daily.streak(won: days(["2026-11-20", "2026-11-21"]), today: today) == 2)
        // A missed day breaks it.
        #expect(Daily.streak(won: days(["2026-11-19", "2026-11-20"]), today: today) == 0)
        #expect(Daily.bestStreak(won: days(["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-10", "2026-11-22"])) == 3)
        #expect(Daily.bestStreak(won: days([])) == 0)
    }

    @Test func sudokuDifficultyFollowsTheWeekday() {
        // 2026-11-23 is a Monday.
        let monday = Daily.Day(key: "2026-11-23")!
        let levels = (0..<7).map { i in Daily.sudokuDifficulty(for: (0..<i).reduce(monday) { d, _ in d.next }) }
        #expect(levels == [.easy, .easy, .medium, .medium, .hard, .hard, .expert])
    }
}
