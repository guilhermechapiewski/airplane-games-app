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
    var swipeBack: SwipeBackBlock = .content
    /// Starts a new game with the current settings, used when the player chose to start over
    /// from the home screen. Same as the menu's New Game (abandoned games count in stats).
    var freshStart: (() -> Void)?

    @State private var showRules = false
    @State private var showStats = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gameLaunch) private var launch
    @Environment(\.openDaily) private var openDaily
    @State private var showDailyDone = false
    private var daily = DailyStore.shared
    private var isDaily: Bool { launch == .daily }
    @State private var handledLaunch = false

    func body(content: Content) -> some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .blocksSwipeBack(swipeBack)
            .navigationTitle(isDaily ? "Daily \(game.title)" : game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isDaily {
                            // The daily puzzle is fixed for the day: no New Game here.
                        } else if newGameOptions.count == 1, let only = newGameOptions.first {
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
                        if game.hasDaily && !isDaily {
                            Divider()
                            Button { openDaily(game) } label: {
                                Label(daily.isDone(game, on: daily.today) ? "Today's Puzzle ✓" : "Today's Puzzle",
                                      systemImage: "calendar")
                            }
                            .accessibilityIdentifier("todaysPuzzle")
                        }
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
            .overlay {
                if showDailyDone {
                    DailyDoneCard(game: game, entry: daily.entry(game, on: daily.today), streak: daily.streak(game)) {
                        withAnimation(.easeOut(duration: 0.2)) { showDailyDone = false }
                    }
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $showStats) {
                StatsSheet(game: game, variants: statsVariants)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                if !handledLaunch {
                    handledLaunch = true
                    if launch == .fresh { freshStart?() }
                    if isDaily {
                        daily.clearOldSaves(game, before: daily.today)
                        showDailyDone = daily.isDone(game, on: daily.today)
                    }
                }
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
        onActiveChange: ((Bool) -> Void)? = nil,
        swipeBack: SwipeBackBlock = .content,
        freshStart: (() -> Void)? = nil
    ) -> some View {
        modifier(GameChrome(game: game, rules: rules, statsVariants: stats,
                            newGameOptions: newGame, onActiveChange: onActiveChange, swipeBack: swipeBack,
                            freshStart: freshStart))
    }
}

/// Shown when today's daily puzzle was already finished: the result, the streak, and a way to
/// replay it just for fun (replays don't change the result or the streak).
private struct DailyDoneCard: View {
    let game: GameID
    let entry: DailyStore.Entry?
    let streak: Int
    let onReplay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: entry?.won == false ? "calendar.badge.exclamationmark" : "calendar.badge.checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(game.accent)
                Text(entry?.won == false ? "Today's puzzle is over" : "Today's puzzle is done")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let time = entry?.time, entry?.won == true {
                    Text("Solved in \(time.clockString)").foregroundStyle(.secondary)
                }
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                Text("A new puzzle arrives tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    Button("Back") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle(color: game.accent))
                    Button("Play It Again", action: onReplay)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityHint("Replays don't change today's result or your streak.")
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 340)
        }
        .accessibilityIdentifier("dailyDone")
    }
}
