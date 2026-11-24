import SwiftUI

/// How a game screen was opened from the home screen.
enum GameLaunch: Hashable {
    /// Continue the saved game, if there is one ("Continue Playing", or nothing to resume).
    case resume
    /// The player chose to start over from the game's card: discard the saved game.
    case fresh
}

/// A navigation destination: which game, and whether to resume or start fresh.
struct GameRoute: Hashable {
    let game: GameID
    var launch: GameLaunch = .resume
}

extension EnvironmentValues {
    /// How the current game screen was opened. Read by `GameChrome` and Nonograms.
    @Entry var gameLaunch: GameLaunch = .resume
}
