import SwiftUI

struct HomeView: View {
    @Binding var path: [GameRoute]
    @State private var inProgress: Set<GameID> = []
    @State private var showSettings = false
    /// A game whose card was tapped while it has a game in progress, awaiting confirmation.
    @State private var confirmNewGame: GameID?

    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !continueGames.isEmpty {
                    section("Continue Playing") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(continueGames) { game in
                                    ContinueChip(game: game) { path.append(GameRoute(game: game)) }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(GameID.allCases) { game in
                        GameCard(game: game, inProgress: inProgress.contains(game)) {
                            openFromCard(game)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        // Title is kept for VoiceOver and back-button context but hidden so the grid starts at the top.
        .navigationTitle("Airplane Games")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog(
            confirmNewGame.map { "Start a new \($0.title) game?" } ?? "",
            isPresented: Binding(get: { confirmNewGame != nil }, set: { if !$0 { confirmNewGame = nil } }),
            titleVisibility: .visible,
            presenting: confirmNewGame
        ) { game in
            Button("Start New Game", role: .destructive) { path.append(GameRoute(game: game, launch: .fresh)) }
                .accessibilityIdentifier("confirmNewGame")
            Button("Resume Game") { path.append(GameRoute(game: game)) }
            Button("Cancel", role: .cancel) {}
        } message: { game in
            Text("Your \(game.title) game in progress will be erased. This can't be undone.")
        }
        .onAppear(perform: refresh)
        .onChange(of: path) { _, newValue in if newValue.isEmpty { refresh() } }
    }

    private var continueGames: [GameID] { GameID.allCases.filter { inProgress.contains($0) } }

    /// A game's card starts a new game. If one is in progress, confirm before erasing it.
    private func openFromCard(_ game: GameID) {
        if game == .nonograms {
            // Nonograms keeps every picture's progress in its library, so nothing is erased:
            // the card opens the library rather than jumping back into the last puzzle.
            path.append(GameRoute(game: game, launch: .fresh))
        } else if inProgress.contains(game) {
            confirmNewGame = game
        } else {
            // Nothing saved, so the game starts fresh on its own.
            path.append(GameRoute(game: game))
        }
    }

    private func refresh() {
        inProgress = Set(GameID.allCases.filter { GameStore.shared.exists(key: $0.saveKey) })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            content()
        }
    }
}

struct GameCard: View {
    let game: GameID
    let inProgress: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: game.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Spacer()
                    if inProgress {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.95))
                            .accessibilityLabel("In progress")
                    }
                }
                Spacer(minLength: 8)
                Text(game.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(game.tagline)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: game.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: game.symbol)
                            .font(.system(size: 90, weight: .black))
                            .foregroundStyle(.white.opacity(0.1))
                            .offset(x: 18, y: 18)
                            .accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: game.accent.opacity(0.35), radius: 10, y: 6)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.title). \(game.tagline)\(inProgress ? ". In progress" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("game.\(game.rawValue)")
    }
}

struct ContinueChip: View {
    let game: GameID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GameBadge(game: game, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text("Resume").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .background(Theme.surface, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Resume \(game.title)")
    }
}
