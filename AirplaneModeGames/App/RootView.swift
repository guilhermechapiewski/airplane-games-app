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
    }
}

/// Maps a game to its screen.
struct GameDestination: View {
    let game: GameID

    var body: some View {
        switch game {
        default:
            ComingSoonView(game: game)
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
