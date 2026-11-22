import SwiftUI

/// An entry in a game's "New Game" menu.
struct NewGameOption: Identifiable {
    let id = UUID()
    let title: String
    var systemImage: String?
    let action: () -> Void
}

/// Standard navigation chrome for every game: title, a menu with
/// New Game / How to Play / Statistics, and lifecycle callbacks that tell
/// the game when it becomes active or inactive (for timers and saving).
struct GameChrome: ViewModifier {
    let game: GameID
    let rules: HowToPlay
    let statsVariants: [StatsVariant]
    let newGameOptions: [NewGameOption]
    var onActiveChange: ((Bool) -> Void)?

    @State private var showRules = false
    @State private var showStats = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if newGameOptions.count == 1, let only = newGameOptions.first {
                            Button { only.action() } label: { Label("New Game", systemImage: "plus.circle") }
                        } else {
                            Menu {
                                ForEach(newGameOptions) { option in
                                    Button { option.action() } label: {
                                        if let image = option.systemImage {
                                            Label(option.title, systemImage: image)
                                        } else {
                                            Text(option.title)
                                        }
                                    }
                                }
                            } label: { Label("New Game", systemImage: "plus.circle") }
                        }
                        Button { showRules = true } label: { Label("How to Play", systemImage: "questionmark.circle") }
                        Button { showStats = true } label: { Label("Statistics", systemImage: "chart.bar") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Game menu")
                    .accessibilityIdentifier("gameMenu")
                }
            }
            .sheet(isPresented: $showRules) {
                HowToPlaySheet(game: game, rules: rules)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showStats) {
                StatsSheet(game: game, variants: statsVariants)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                warmUpFeedback()
                onActiveChange?(scenePhase == .active)
            }
            .onDisappear { onActiveChange?(false) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { warmUpFeedback() }
                onActiveChange?(phase == .active)
            }
            .onChange(of: showRules) { _, shown in onActiveChange?(!shown && !showStats && scenePhase == .active) }
            .onChange(of: showStats) { _, shown in onActiveChange?(!shown && !showRules && scenePhase == .active) }
    }

    /// The audio engine stops in the background; restart it (and wake the haptics) before the
    /// player's first touch rather than during it.
    private func warmUpFeedback() {
        SoundEngine.shared.warmUp()
        Haptics.prepare()
    }
}

extension View {
    func gameChrome(
        _ game: GameID,
        rules: HowToPlay,
        stats: [StatsVariant] = [StatsVariant()],
        newGame: [NewGameOption],
        onActiveChange: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(GameChrome(game: game, rules: rules, statsVariants: stats,
                            newGameOptions: newGame, onActiveChange: onActiveChange))
    }
}
