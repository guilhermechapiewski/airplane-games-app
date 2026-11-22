import Foundation

struct GameStats: Codable, Equatable, Sendable {
    var played = 0
    var won = 0
    var currentStreak = 0
    var bestStreak = 0
    var bestScore: Int?
    var bestTime: TimeInterval?
    var totalTime: TimeInterval = 0

    var winRate: Double { played == 0 ? 0 : Double(won) / Double(played) }
}

/// Local statistics per game (and optional variant such as difficulty).
@MainActor @Observable
final class StatsStore {
    static let shared = StatsStore()

    private(set) var all: [String: GameStats]
    private let store: GameStore
    private static let key = "stats"

    init(store: GameStore = .shared) {
        self.store = store
        self.all = store.load([String: GameStats].self, key: Self.key) ?? [:]
    }

    static func key(_ game: GameID, variant: String?) -> String {
        if let variant { "\(game.rawValue).\(variant)" } else { game.rawValue }
    }

    func stats(for game: GameID, variant: String? = nil) -> GameStats {
        all[Self.key(game, variant: variant)] ?? GameStats()
    }

    /// Records a finished game.
    /// - Parameters:
    ///   - score: optional score; `bestScore` keeps the max.
    ///   - time: optional duration; `bestTime` keeps the minimum among *won* games.
    func record(_ game: GameID, variant: String? = nil, won: Bool, score: Int? = nil, time: TimeInterval? = nil) {
        let key = Self.key(game, variant: variant)
        var s = all[key] ?? GameStats()
        s.played += 1
        if won {
            s.won += 1
            s.currentStreak += 1
            s.bestStreak = max(s.bestStreak, s.currentStreak)
            if let time { s.bestTime = min(s.bestTime ?? .infinity, time) }
        } else {
            s.currentStreak = 0
        }
        if let score { s.bestScore = max(s.bestScore ?? score, score) }
        if let time { s.totalTime += time }
        all[key] = s
        store.save(all, key: Self.key)
    }

    /// Updates the best score without counting a game (e.g. live high score in 2048).
    func submitScore(_ game: GameID, variant: String? = nil, score: Int) {
        let key = Self.key(game, variant: variant)
        var s = all[key] ?? GameStats()
        guard score > (s.bestScore ?? Int.min) else { return }
        s.bestScore = score
        all[key] = s
        store.save(all, key: Self.key)
    }

    /// Game-specific statistics stored outside `StatsStore` that "Reset All Statistics" also clears.
    /// (Puzzle progress such as solved Nonograms is gameplay state, not statistics, and is kept.)
    static let auxiliaryKeys = ["wordGuess.distribution", "chess.records"]

    func reset() {
        all = [:]
        store.remove(key: Self.key)
        Self.auxiliaryKeys.forEach { store.remove(key: $0) }
    }
}
