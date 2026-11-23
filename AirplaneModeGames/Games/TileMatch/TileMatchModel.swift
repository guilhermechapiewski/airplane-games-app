import SwiftUI
import UIKit
import GameLogic

@MainActor @Observable
final class TileMatchModel {
    typealias Logic = TileMatch

    private struct Saved: Codable {
        var state: Logic.State
        var clock: GameClock
        var started: Bool
    }

    /// A matched tile on its way out, flying toward its partner.
    struct Vanishing: Identifiable {
        let tile: Logic.Tile
        let partner: Logic.Tile
        var id: Int { tile.id }
    }

    private(set) var state: Logic.State
    private(set) var clock = GameClock()
    private(set) var started = false

    private(set) var selected: Int?
    private(set) var hint: Logic.Pair?
    private(set) var vanishing: [Vanishing] = []
    /// Per tile, the token of its latest shake (a change triggers the animation).
    private(set) var shakeTokens: [Int: Int] = [:]
    private var shakeCounter = 0
    /// Identifies the current deal; tiles of a new deal are new views.
    private(set) var dealToken = 0
    /// True briefly after a new deal so tiles can cascade in.
    private(set) var isDealing = false
    /// Bumped on every board change so animations can key off it.
    private(set) var changeToken = 0

    // Cached queries, refreshed after each change.
    private(set) var freeIDs: Set<Int> = []
    private(set) var uncoveredIDs: Set<Int> = []
    private(set) var availableMatches = 0

    var showWin = false
    private(set) var showStuck = false
    private(set) var stuckIsHopeless = false
    private(set) var lastWinWasBest = false

    private let store: GameStore
    private let stats: StatsStore
    let game = GameID.tileMatch
    private static let layoutKey = "tileMatch.layout"

    /// Today, when this is the daily deal (Lantern layout, fixed by the date, saved separately).
    let daily: Daily.Day?
    private var saveKey: String { daily.map { game.dailySaveKey($0) } ?? game.saveKey }
    static let dailyLayout = Logic.LayoutID.lantern

    init(daily: Daily.Day? = nil, store: GameStore = .shared, stats: StatsStore = .shared) {
        self.daily = daily
        self.store = store
        self.stats = stats
        if let saved = store.load(Saved.self, key: daily.map { GameID.tileMatch.dailySaveKey($0) } ?? GameID.tileMatch.saveKey),
           !saved.state.isCleared {
            state = saved.state
            clock = saved.clock
            started = saved.started
        } else if let daily {
            state = .newGame(layout: Self.dailyLayout, seed: GameID.tileMatch.dailySeed(daily))
        } else {
            state = .newGame(layout: Self.preferredLayout)
        }
        refresh()
        showStuck = !state.isCleared && availableMatches == 0
    }

    // MARK: Derived

    var layout: Logic.LayoutID { state.layout }
    var tilesLeft: Int { state.tiles.count }
    var canUndo: Bool { !state.history.isEmpty && !showWin }
    var bestTime: TimeInterval? { stats.stats(for: game, variant: layout.rawValue).bestTime }

    private static var preferredLayout: Logic.LayoutID {
        if let raw = UserDefaults.standard.string(forKey: layoutKey), let id = Logic.LayoutID(rawValue: raw) {
            return id
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .butterfly : .lantern
    }

    // MARK: Actions

    func tap(_ id: Int) {
        guard !showWin, !showStuck, let tile = state.tile(id) else { return }
        beginIfNeeded()
        guard freeIDs.contains(id) else {
            shake([id])
            Feedback.play(.invalid)
            return
        }
        guard let current = selected else {
            selected = id
            Feedback.play(.select)
            return
        }
        if current == id {
            selected = nil
            Feedback.play(.tap)
            return
        }
        guard let other = state.tile(current), other.face.matches(tile.face) else {
            // Not a match: shake both and move the selection to the newly tapped tile.
            shake([current, id])
            selected = id
            Feedback.play(.invalid)
            return
        }
        match(other, tile)
    }

    private func match(_ a: Logic.Tile, _ b: Logic.Tile) {
        guard state.match(a.id, b.id) else { return }
        selected = nil
        hint = nil
        vanishing.append(Vanishing(tile: a, partner: b))
        vanishing.append(Vanishing(tile: b, partner: a))
        let removed: Set<Int> = [a.id, b.id]
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(520))
            self?.vanishing.removeAll { removed.contains($0.id) }
        }
        refresh()

        if state.isCleared {
            finishWin()
        } else {
            Feedback.play(.pop)
            checkStuck()
        }
        persist()
    }

    func showHint() {
        guard !showWin, !showStuck else { return }
        guard let pair = state.hint() else {
            checkStuck()
            return
        }
        beginIfNeeded()
        selected = nil
        hint = pair
        Feedback.play(.tap)
        let token = changeToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.changeToken == token else { return }
            self.hint = nil
        }
    }

    func shuffle() {
        guard !showWin, state.tiles.count >= 2 else { return }
        beginIfNeeded()
        let result = state.shuffle()
        guard result != .impossible else {
            stuckIsHopeless = true
            showStuck = true
            Feedback.play(.invalid)
            return
        }
        selected = nil
        hint = nil
        showStuck = false
        refresh()
        Feedback.play(.clear)
        checkStuck()
        persist()
    }

    func undo() {
        guard canUndo else { return }
        state.undo()
        selected = nil
        hint = nil
        vanishing = []
        showStuck = false
        stuckIsHopeless = false
        refresh()
        Feedback.play(.flip)
        clock.start()
        persist()
    }

    /// Deals a new game. On the daily, this restarts today's deal.
    func newGame(layout: Logic.LayoutID? = nil) {
        if daily == nil && started && !state.isCleared && !showWin {
            // Count an abandoned game that had progress.
            stats.record(game, variant: self.layout.rawValue, won: false, time: clock.elapsed())
        }
        if let daily {
            state = .newGame(layout: Self.dailyLayout, seed: game.dailySeed(daily))
        } else {
            let chosen = layout ?? self.layout
            UserDefaults.standard.set(chosen.rawValue, forKey: Self.layoutKey)
            state = .newGame(layout: chosen)
        }
        clock = GameClock()
        started = false
        selected = nil
        hint = nil
        vanishing = []
        showWin = false
        showStuck = false
        stuckIsHopeless = false
        lastWinWasBest = false
        shakeTokens = [:]
        dealToken += 1
        isDealing = true
        let token = dealToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard let self, self.dealToken == token else { return }
            self.isDealing = false
        }
        refresh()
        store.remove(key: saveKey)
    }

    func setActive(_ active: Bool) {
        if active, started, !showWin, !showStuck { clock.start() } else { clock.pause() }
        if !active { persist() }
    }

    // MARK: Helpers

    private func beginIfNeeded() {
        if !started {
            started = true
            persist()
        }
        clock.start()
    }

    private func shake(_ ids: Set<Int>) {
        shakeCounter += 1
        for id in ids { shakeTokens[id] = shakeCounter }
    }

    private func refresh() {
        freeIDs = state.freeTileIDs
        uncoveredIDs = state.uncoveredTileIDs
        availableMatches = state.availableMatches.count
        changeToken += 1
    }

    private func checkStuck() {
        guard !state.isCleared, availableMatches == 0 else { return }
        stuckIsHopeless = false
        showStuck = true
        clock.pause()
        Haptics.warning()
    }

    private func finishWin() {
        clock.pause()
        let time = clock.elapsed()
        let previousBest = bestTime
        if let daily {
            DailyStore.shared.record(game, on: daily, won: true, time: time)
        } else {
            stats.record(game, variant: layout.rawValue, won: true, time: time)
        }
        lastWinWasBest = previousBest.map { time < $0 } ?? true
        store.remove(key: saveKey)
        Feedback.play(.win)
        Task { @MainActor [weak self] in
            // Let the last pair finish vanishing before the celebration.
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.state.isCleared else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.showWin = true }
        }
    }

    private func persist() {
        if state.isCleared {
            store.remove(key: saveKey)
        } else if started {
            store.save(Saved(state: state, clock: clock, started: started), key: saveKey)
        }
    }
}
