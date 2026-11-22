import SwiftUI

struct RootView: View {
    @State private var path: [GameID] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: GameID.self) { game in
                    GameDestination(game: game)
                }
        }
        .onAppear(perform: openGameFromLaunchArguments)
    }

    /// `-openGame <id>` jumps straight into a game (used by UI tests and screenshots).
    private func openGameFromLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard path.isEmpty, let i = args.firstIndex(of: "-openGame"), i + 1 < args.count,
              let game = GameID(rawValue: args[i + 1]) else { return }
        path = [game]
    }
}

/// Maps a game to its screen.
struct GameDestination: View {
    let game: GameID

    var body: some View {
        switch game {
        case .twentyFortyEight: TwentyFortyEightView()
        case .sudoku: SudokuView()
        case .solitaire: SolitaireView()
        case .blocks: BlockPuzzleView()
        case .tileMatch: TileMatchView()
        case .minesweeper: MinesweeperView()
        case .chess: ChessView()
        case .wordGuess: WordGuessView()
        case .nonograms: NonogramsView()
        case .wordSearch: WordSearchView()
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
