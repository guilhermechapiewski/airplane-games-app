import SwiftUI
import GameLogic

struct DotsAndBoxesView: View {
    @State private var model = DotsAndBoxesModel()

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15 && geo.size.width >= 640
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
        .gameChrome(.dotsAndBoxes, rules: Self.rules, stats: Self.statsVariants,
                    newGame: [
                        NewGameOption(title: "Set Up New Game…", systemImage: "slider.horizontal.3") { model.showSetup = true },
                        NewGameOption(title: "Play Again", systemImage: "arrow.clockwise") { model.rematch() },
                    ],
                    onActiveChange: model.setActive,
                    freshStart: { model.rematch() })
        .sheet(isPresented: $model.showSetup) {
            DotsSetupSheet(model: model)
                .presentationDetents([.large])
        }
    }

    // MARK: Layouts

    private func tallLayout(_ size: CGSize) -> some View {
        let padding: CGFloat = 16
        let reserved: CGFloat = 230
        let boardSide = max(220, min(size.width - padding * 2, size.height - reserved, 720))
        return VStack(spacing: 12) {
            DotsScoreboard(model: model)
                .frame(maxWidth: boardSide)
            Spacer(minLength: 0)
            DotsBoardView(model: model, side: boardSide)
            DotsStatusLine(model: model)
                .padding(.top, 6)
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, padding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wideLayout(_ size: CGSize) -> some View {
        let panelWidth: CGFloat = min(320, max(260, size.width * 0.28))
        let boardSide = max(260, min(size.height - 48, size.width - panelWidth - 80, 720))
        return HStack(spacing: 32) {
            DotsBoardView(model: model, side: boardSide)
            VStack(spacing: 16) {
                DotsScoreboard(model: model, vertical: true)
                DotsStatusLine(model: model)
                Spacer(minLength: 0)
                controls
            }
            .frame(width: panelWidth, height: boardSide)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward", tint: DotsTheme.accent) {
                model.undo()
            }
            .disabled(!model.canUndo)
            .accessibilityIdentifier("undo")
            ToolButton(title: "New", systemImage: "plus", tint: DotsTheme.accent) {
                model.showSetup = true
            }
            .accessibilityLabel("New Game")
        }
    }

    // MARK: Result

    @ViewBuilder private var resultOverlay: some View {
        if model.showResult, model.isOver {
            let win = model.resultIsWin
            ResultOverlay(mood: win == true ? .win : (win == false ? .loss : .neutral),
                          title: model.outcomeTitle, subtitle: subtitle,
                          details: [(model.name(for: .one), "\(model.game.score(.one))"),
                                    (model.name(for: .two), "\(model.game.score(.two))")],
                          tint: DotsTheme.accent) {
                VStack(spacing: 10) {
                    Button("Play Again") { model.rematch() }
                        .buttonStyle(PrimaryButtonStyle(color: DotsTheme.accent))
                        .accessibilityIdentifier("result.playAgain")
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

    private var subtitle: String {
        let size = "\(model.game.rows)×\(model.game.cols)"
        if model.setup.isComputer { return "\(model.setup.level.title) computer · \(size) board" }
        return "Pass & Play · \(size) board"
    }

    // MARK: Content

    static let statsVariants: [StatsVariant] =
        DotsAndBoxes.Level.allCases.map {
            StatsVariant(key: DotsAndBoxesModel.statsKey($0), title: "vs. \($0.title) Computer")
        }
        + [StatsVariant(key: "passAndPlay", title: "Pass & Play", showsWins: false)]

    static let rules = HowToPlay(
        summary: "Take turns joining two neighboring dots. Close a box to claim it and go again. Most boxes wins.",
        sections: [
            .init(title: "Playing", symbol: "hand.tap", points: [
                "Tap near a gap between two dots to draw a line there.",
                "Drawing the fourth side of a box claims it — and you move again.",
                "Undo takes back your last line (and the computer's reply).",
            ]),
            .init(title: "Don't hand out boxes", symbol: "exclamationmark.triangle", points: [
                "Drawing a box's third side lets your opponent take it. Early on, play lines that don't.",
                "Sooner or later every line gives something away. Then give away as little as you can.",
            ]),
            .init(title: "Chains", symbol: "link", points: [
                "Boxes joined in a corridor form a chain: open it and your opponent takes the lot, box after box. A loop is a chain that closes on itself.",
                "Handing over a long chain (three or more boxes) usually decides the game, so sacrifice short ones first.",
                "Whoever is forced to open the first long chain usually loses. Strong players count chains early.",
            ]),
            .init(title: "The double-cross", symbol: "arrow.triangle.branch", points: [
                "When you're given a long chain, take all but the last two boxes, then draw the line at the far end instead.",
                "Your opponent gets those two boxes, but then has to open the next chain for you. In a loop, leave four.",
            ]),
            .init(title: "Winning", symbol: "trophy", points: [
                "The game ends when every line is drawn. Most boxes wins; on 4×4 and 6×6 boards a tie is possible.",
            ]),
        ]
    )
}

/// Both players' scores; the one to move is highlighted.
struct DotsScoreboard: View {
    let model: DotsAndBoxesModel
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            card(.one)
            card(.two)
        }
    }

    private func card(_ player: DotsAndBoxes.Player) -> some View {
        let isTurn = !model.isOver && model.current == player
        let color = DotsTheme.color(player)
        let score = model.game.score(player)
        let isWinner = model.isOver && model.game.winner == player
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(color)
                if model.isComputer(player) {
                    Image(systemName: "cpu")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text(model.initial(for: player))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name(for: player))
                    .font(.subheadline.weight(.bold))
                Text(caption(for: player, isTurn: isTurn, isWinner: isWinner))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isTurn ? color : .secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(score)")
                .font(.system(.title, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTurn ? color : Theme.hairline.opacity(0.6), lineWidth: isTurn ? 2.5 : 1)
        }
        .overlay(alignment: .top) {
            // A small notch above the active card: position, not just colour, shows the turn.
            if isTurn {
                Capsule().fill(color).frame(width: 28, height: 5).offset(y: -2.5)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isTurn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.name(for: player))
        .accessibilityValue("\(score) \(score == 1 ? "box" : "boxes")" + (isTurn ? ", to move" : "") + (isWinner ? ", winner" : ""))
        .accessibilityIdentifier("score.\(player == .one ? "one" : "two")")
    }

    private func caption(for player: DotsAndBoxes.Player, isTurn: Bool, isWinner: Bool) -> String {
        if model.isOver { return isWinner ? "Winner" : (model.game.winner == nil ? "Tie" : "") }
        if isTurn {
            if model.isComputer(player) { return model.isThinking ? "Thinking…" : "To move" }
            return model.setup.isComputer ? "Your turn" : "To move"
        }
        if model.isComputer(player) { return model.setup.level.title }
        return "Waiting"
    }
}

/// One line of status under the board ("Your turn", "Box! Go again").
struct DotsStatusLine: View {
    let model: DotsAndBoxesModel

    var body: some View {
        let color = model.isOver ? DotsTheme.accent : DotsTheme.color(model.current)
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(model.statusText)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
            if model.isThinking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
        .frame(minHeight: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.statusText)
        .accessibilityIdentifier("turnStatus")
    }
}
