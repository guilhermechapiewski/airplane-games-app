import GameLogic
import SwiftUI

struct StatsSheet: View {
    let game: GameID
    /// Ordered variants to show (e.g. difficulties). `nil` entry = the game without a variant.
    let variants: [StatsVariant]
    @Environment(\.dismiss) private var dismiss
    private var stats = StatsStore.shared
    private var daily = DailyStore.shared

    init(game: GameID, variants: [StatsVariant]) {
        self.game = game
        self.variants = variants
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if game.hasDaily { dailyCard }
                    ForEach(variants.filter { !$0.hidesWhenEmpty || stats.stats(for: game, variant: $0.key).played > 0 }) { variant in
                        card(variant)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("\(game.title) Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Daily puzzle results, counted by day.
    private var dailyCard: some View {
        let best = stats.stats(for: game, variant: StatsVariant.dailyKey).bestTime
        return VStack(alignment: .leading, spacing: 12) {
            Label("Daily Puzzle", systemImage: "calendar").font(.headline).foregroundStyle(game.accent)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("Played", "\(daily.playedCount(game))")
                tile("Solved", "\(daily.wonCount(game))")
                tile("Streak", "\(daily.streak(game))")
                tile("Best Streak", "\(daily.bestStreak(game))")
                tile("Best Time", best.map { $0.clockString } ?? "–")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("dailyStats")
    }

    private func card(_ variant: StatsVariant) -> some View {
        let s = stats.stats(for: game, variant: variant.key)
        return VStack(alignment: .leading, spacing: 12) {
            if let title = variant.title {
                Text(title).font(.headline).foregroundStyle(game.accent)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("Played", "\(s.played)")
                if variant.showsWins { tile("Won", "\(s.won)") }
                if variant.showsWins { tile("Win %", s.played == 0 ? "–" : "\(Int((s.winRate * 100).rounded()))%") }
                if variant.showsWins { tile("Streak", "\(s.currentStreak)") }
                if variant.showsWins { tile("Best Streak", "\(s.bestStreak)") }
                if variant.showsScore { tile("Best Score", s.bestScore.map { "\($0)" } ?? "–") }
                if variant.showsTime { tile("Best Time", s.bestTime.map { $0.clockString } ?? "–") }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct StatsVariant: Identifiable {
    var key: String?
    var title: String?
    var showsWins = true
    var showsScore = false
    var showsTime = false
    /// Show this card only once a game has been played with it.
    var hidesWhenEmpty = false
    var id: String { key ?? "_" }

    /// Statistics variant that daily puzzle wins are recorded under.
    static let dailyKey = "daily"

    static func difficulties(showsTime: Bool = true) -> [StatsVariant] {
        GameLogic.Difficulty.allCases.map {
            StatsVariant(key: $0.rawValue, title: $0.title, showsTime: showsTime)
        }
    }
}
