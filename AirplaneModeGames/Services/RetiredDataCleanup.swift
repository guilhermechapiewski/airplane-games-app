import Foundation

/// Removes data left on the device by features that no longer exist. Runs once, at launch, before
/// any store is loaded.
@MainActor
enum RetiredDataCleanup {
    static let doneKey = "cleanup.dailyPuzzlesRemoved"

    static func run(store: GameStore = .shared, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        // The former daily puzzles: their records ("daily.records") and saves ("daily.<game>.<day>").
        store.removeKeys { $0.hasPrefix("daily.") }
        // …and their statistics, stored as the "daily" variant of each game ("<game>.daily").
        if var stats = store.load([String: GameStats].self, key: StatsStore.storageKey) {
            let before = stats.count
            stats = stats.filter { !$0.key.hasSuffix(".daily") }
            if stats.count != before { store.save(stats, key: StatsStore.storageKey) }
        }
        defaults.set(true, forKey: doneKey)
    }
}
