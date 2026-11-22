import SwiftUI
import GameLogic

struct ChessView: View {
    @State private var model = ChessModel()
    @State private var confirmResign = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.2 && geo.size.width >= 640
            Group {
                if wide {
                    wideLayout(geo.size)
                } else {
                    tallLayout(geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay { resultOverlay }
        .gameChrome(.chess, rules: Self.rules, stats: Self.statsVariants,
                    newGame: [
                        NewGameOption(title: "Set Up New Game…", systemImage: "slider.horizontal.3") { model.showSetup = true },
                        NewGameOption(title: "Rematch", systemImage: "arrow.clockwise") { withAnimation { model.rematch() } },
                    ],
                    onActiveChange: model.setActive,
                    freshStart: { model.rematch() })
        .sheet(isPresented: $model.showSetup) {
            ChessSetupSheet(model: model)
                .presentationDetents([.large])
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { model.resign() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text(model.setup.isComputer ? "The computer will be awarded the win." : "\(model.sideToMove.name) resigns and \(model.sideToMove.opponent.name) wins.")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: model.bottomSide)
    }

    // MARK: Layouts

    private func tallLayout(_ size: CGSize) -> some View {
        let padding: CGFloat = 12
        let reserved: CGFloat = 250
        let boardSide = max(200, min(size.width - padding * 2, size.height - reserved, 720))
        let contentWidth = boardSide
        return VStack(spacing: 10) {
            ChessPlayerBar(model: model, side: model.bottomSide.opponent)
                .frame(width: contentWidth)
            Spacer(minLength: 0)
            board(side: boardSide - boardSide * 0.044)
            Spacer(minLength: 0)
            ChessPlayerBar(model: model, side: model.bottomSide)
                .frame(width: contentWidth)
            ChessMoveStrip(model: model)
                .frame(width: contentWidth)
            controls
                .padding(.top, 2)
        }
        .padding(.horizontal, padding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wideLayout(_ size: CGSize) -> some View {
        let panelWidth: CGFloat = min(340, max(270, size.width * 0.3))
        let boardSide = max(240, min(size.height - 40, size.width - panelWidth - 72))
        return HStack(spacing: 28) {
            board(side: boardSide - boardSide * 0.044)
            VStack(spacing: 12) {
                ChessPlayerBar(model: model, side: model.bottomSide.opponent)
                ChessMoveTable(model: model)
                    .frame(maxHeight: .infinity)
                ChessPlayerBar(model: model, side: model.bottomSide)
                controls
            }
            .frame(width: panelWidth, height: boardSide)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func board(side: CGFloat) -> some View {
        ChessBoardView(model: model, side: side, reduceMotion: reduceMotion)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward", tint: ChessTheme.accent) {
                withAnimation(.easeInOut(duration: 0.24)) { model.undo() }
            }
            .disabled(!model.canUndo)
            if model.setup.mode == .passAndPlay {
                ToolButton(title: "Rotate", systemImage: "arrow.triangle.2.circlepath",
                           isActive: model.autoRotate, tint: ChessTheme.accent) {
                    model.autoRotate.toggle()
                    Feedback.play(.tap)
                }
                .accessibilityValue(model.autoRotate ? "On, board turns for each player" : "Off")
            }
            ToolButton(title: "Resign", systemImage: "flag", tint: ChessTheme.accent) {
                confirmResign = true
            }
            .disabled(!model.canResign)
            ToolButton(title: "New", systemImage: "plus", tint: ChessTheme.accent) {
                model.showSetup = true
            }
            .accessibilityLabel("New Game")
        }
    }

    // MARK: Result

    @ViewBuilder private var resultOverlay: some View {
        if model.showResult, let outcome = model.outcome {
            let win = model.resultIsWin
            ResultOverlay(mood: win == true ? .win : (win == false ? .loss : .neutral), title: model.outcomeTitle(outcome), subtitle: subtitle(for: outcome),
                          details: details, tint: ChessTheme.accent) {
                VStack(spacing: 10) {
                    Button("Rematch") { withAnimation { model.rematch() } }
                        .buttonStyle(PrimaryButtonStyle(color: ChessTheme.accent))
                    HStack(spacing: 10) {
                        Button("New Game") {
                            model.showResult = false
                            model.showSetup = true
                        }
                        Button("View Board") {
                            withAnimation { model.showResult = false }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity)
        }
    }

    private func subtitle(for outcome: Chess.Outcome) -> String {
        switch outcome {
        case .checkmate(let winner): "\(winner.name) delivered checkmate."
        case .resignation(let winner): "\(winner.opponent.name) resigned."
        case .stalemate: "Stalemate — no legal moves, but no check."
        case .fiftyMoveRule: "50 moves without a capture or pawn move."
        case .threefoldRepetition: "The same position occurred three times."
        case .insufficientMaterial: "Neither side has enough material to mate."
        }
    }

    private var details: [(String, String)] {
        let moves = (model.game.moves.count + 1) / 2
        var d = [("Moves", "\(moves)")]
        if model.setup.isComputer { d.append(("Level", model.setup.level.title)) }
        return d
    }

    // MARK: Content

    static let statsVariants: [StatsVariant] =
        Chess.Level.allCases.map { StatsVariant(key: "level\($0.rawValue)", title: "vs. \($0.title)") }
        + [StatsVariant(key: "passAndPlay", title: "Pass & Play", showsWins: false)]

    static let rules = HowToPlay(
        summary: "Checkmate the opposing king. Play the computer at five levels, or a friend on the same device.",
        sections: [
            .init(title: "Moving", symbol: "hand.tap", points: [
                "Tap a piece to see its legal moves, then tap a highlighted square — or drag the piece there.",
                "Dots mark empty squares you can move to; rings mark captures.",
                "Undo takes back your last move (and the computer's reply).",
            ]),
            .init(title: "Special moves", symbol: "sparkles", points: [
                "Castling: move the king two squares toward a rook that hasn't moved. Not allowed out of, through, or into check.",
                "En passant: a pawn that just advanced two squares can be captured as if it moved one.",
                "A pawn reaching the last rank promotes to a queen, rook, bishop or knight.",
            ]),
            .init(title: "Game end", symbol: "flag.checkered", points: [
                "Checkmate wins. Stalemate, threefold repetition, the 50-move rule and insufficient material are draws.",
                "You can resign at any time from the flag button.",
            ]),
        ]
    )
}

