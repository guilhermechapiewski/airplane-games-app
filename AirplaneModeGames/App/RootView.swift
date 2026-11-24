import GameLogic
import SwiftUI

struct RootView: View {
    @State private var path: [GameRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: GameRoute.self) { route in
                    GameDestination(game: route.game, daily: route.launch == .daily ? Daily.Day() : nil)
                        .environment(\.gameLaunch, route.launch)
                }
        }
        .environment(\.openDaily, OpenDailyAction { game in path.append(GameRoute(game: game, launch: .daily)) })
        .onAppear(perform: openGameFromLaunchArguments)
    }

    /// `-openGame <id>` jumps straight into a game (used by UI tests and screenshots);
    /// adding `-daily` opens its daily puzzle instead.
    private func openGameFromLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard path.isEmpty, let i = args.firstIndex(of: "-openGame"), i + 1 < args.count,
              let game = GameID(rawValue: args[i + 1]) else { return }
        path = [args.contains("-daily") ? GameRoute(game: game, launch: .daily) : GameRoute(game: game)]
    }
}

/// Maps a game to its screen.
struct GameDestination: View {
    let game: GameID
    /// Today, when this is the daily puzzle.
    var daily: Daily.Day?

    var body: some View {
        switch game {
        case .twentyFortyEight: TwentyFortyEightView()
        case .sudoku: SudokuView(daily: daily)
        case .solitaire: SolitaireView(daily: daily)
        case .freeCell: FreeCellView()
        case .blocks: BlockPuzzleView()
        case .tileMatch: TileMatchView(daily: daily)
        case .waterSort: WaterSortView(daily: daily)
        case .dotsAndBoxes: DotsAndBoxesView()
        case .wordWheel: WordWheelView(daily: daily)
        case .minesweeper: MinesweeperView(daily: daily)
        case .chess: ChessView()
        case .wordGuess: WordGuessView(daily: daily)
        case .nonograms: NonogramsView()
        case .wordSearch: WordSearchView(daily: daily)
        case .snake: SnakeView()
        case .hangman: HangmanView()
        }
    }
}

struct ComingSoonView: View {
    let game: GameID
    var body: some View {
        VStack(spacing: 16) {
            GameBadge(game: game, size: 88)
            Text(game.title).font(.title.bold())
            Text("Coming soon").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(game.title)
    }
}
