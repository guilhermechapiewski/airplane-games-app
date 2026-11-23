import Foundation

/// Daily puzzles: one per game per calendar day, generated from the date so every player gets
/// the same puzzle that day, with no network needed.
public enum Daily {
    /// A calendar day ("2026-11-22"), independent of time zones once created.
    public struct Day: Hashable, Comparable, Codable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int

        /// The day `date` falls on in `calendar` (the device's own by default).
        public init(_ date: Date = .now, calendar: Calendar = .current) {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            self.init(year: c.year!, month: c.month!, day: c.day!)
        }

        init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        public init?(key: String) {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
            self.init(year: parts[0], month: parts[1], day: parts[2])
        }

        public var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

        /// Noon UTC on this day, for calendar arithmetic that can't trip over daylight saving.
        var noon: Date {
            Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }

        public var next: Day { Day(Self.utc.date(byAdding: .day, value: 1, to: noon)!, calendar: Self.utc) }
        public var previous: Day { Day(Self.utc.date(byAdding: .day, value: -1, to: noon)!, calendar: Self.utc) }
        /// 1 = Sunday … 7 = Saturday.
        public var weekday: Int { Self.utc.component(.weekday, from: noon) }

        public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

        static let utc: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC")!
            return c
        }()
    }

    /// The seed for `game`'s puzzle on `day`. Never change this: it would change everyone's puzzles.
    public static func seed(day: Day, game: String) -> UInt64 {
        fnv1a("\(day.key)|\(game)")
    }

    /// 64-bit FNV-1a: stable across runs, devices and Swift versions (unlike `Hasher`).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Consecutive won days ending today, or yesterday if today isn't won yet.
    public static func streak(won: Set<Day>, today: Day) -> Int {
        var day = won.contains(today) ? today : today.previous
        var count = 0
        while won.contains(day) {
            count += 1
            day = day.previous
        }
        return count
    }

    /// The longest run of consecutive won days.
    public static func bestStreak(won: Set<Day>) -> Int {
        var best = 0
        for day in won where !won.contains(day.previous) {
            var length = 1
            var d = day.next
            while won.contains(d) { length += 1; d = d.next }
            best = max(best, length)
        }
        return best
    }

    /// Daily Sudoku gets harder through the week: easy Monday–Tuesday, medium Wednesday–Thursday,
    /// hard Friday–Saturday, expert on Sunday.
    public static func sudokuDifficulty(for day: Day) -> Difficulty {
        switch day.weekday {
        case 2, 3: .easy
        case 4, 5: .medium
        case 6, 7: .hard
        default: .expert
        }
    }
}
