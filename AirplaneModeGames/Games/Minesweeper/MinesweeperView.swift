import SwiftUI
import GameLogic

struct MinesweeperView: View {
    @State private var model = MinesweeperModel()
    @State private var zoomRequest: MinesweeperBoard.ZoomRequest?
    @State private var canZoom = false
    @State private var isZoomed = false
    @State private var pendingLevel: Minesweeper.Level?

    private let accent = MinePalette.win

    var body: some View {
        VStack(spacing: 12) {
            header
            MinesweeperBoard(model: model, zoomRequest: $zoomRequest) { zoomable, zoomed in
                canZoom = zoomable
                isZoomed = zoomed
            }
            .frame(maxWidth: boardMaxWidth)
            .accessibilityIdentifier("minefield")
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay { overlay }
        .gameChrome(.minesweeper, rules: Self.rules,
                    stats: MinesweeperModel.statsVariants,
                    newGame: Minesweeper.Level.allCases.map { level in
                        NewGameOption(title: "\(level.title) · \(level.cols)×\(level.rows)") { start(level) }
                    },
                    onActiveChange: model.setActive)
        .confirmationDialog("Start a new \(pendingLevel?.title ?? "") game?",
                            isPresented: Binding(get: { pendingLevel != nil }, set: { if !$0 { pendingLevel = nil } }),
                            titleVisibility: .visible) {
            Button("New Game", role: .destructive) {
                if let level = pendingLevel { withAnimation { model.newGame(level: level) } }
                pendingLevel = nil
            }
        } message: {
            Text("Your current game will count as a loss.")
        }
    }

    /// Keeps the beginner board compact on iPad while larger boards use the space.
    private var boardMaxWidth: CGFloat {
        switch model.level {
        case .beginner: 560
        case .intermediate: 760
        case .expert: 820
        }
    }

    private func start(_ level: Minesweeper.Level) {
        if model.hasProgress {
            pendingLevel = level
        } else {
            withAnimation { model.newGame(level: level) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            levelMenu
            Spacer(minLength: 0)
            StatPill(title: "Mines", value: "\(model.state.minesLeft)", tint: MinePalette.flag)
                .animation(.snappy, value: model.state.minesLeft)
                .accessibilityIdentifier("minesLeft")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatPill(title: "Time", value: model.clock.elapsed(at: context.date).clockString)
            }
            .accessibilityIdentifier("timer")
        }
    }

    private var levelMenu: some View {
        Menu {
            ForEach(Minesweeper.Level.allCases) { level in
                Button {
                    start(level)
                } label: {
                    if level == model.level {
                        Label("\(level.title) · \(level.mines) mines", systemImage: "checkmark")
                    } else {
                        Text("\(level.title) · \(level.mines) mines")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("LEVEL")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(model.level.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Level")
        .accessibilityValue(model.level.title)
        .tint(.primary)
        .accessibilityIdentifier("levelMenu")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 14) {
            ModeToggle(mode: Binding(get: { model.mode }, set: { model.mode = $0 }))
            Spacer(minLength: 0)
            if canZoom {
                ToolButton(title: isZoomed ? "Fit" : "Zoom",
                           systemImage: isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass") {
                    zoomRequest = isZoomed ? .fit : .comfortable
                }
                .accessibilityIdentifier("zoomButton")
            }
            ToolButton(title: "New", systemImage: "arrow.clockwise") { start(model.level) }
                .accessibilityIdentifier("newGameButton")
        }
        .frame(maxWidth: 560)
    }

    // MARK: Overlay

    @ViewBuilder private var overlay: some View {
        if model.showResult {
            let won = model.status == .won
            let best = model.bestTime
            ResultOverlay(mood: won ? .win : .loss,
                          title: won ? "Field Cleared!" : "Boom!",
                          subtitle: won
                              ? (model.isNewBest ? "New best time for \(model.level.title)!" : "Every mine found on \(model.level.title).")
                              : "You hit a mine. Shake it off and try again.",
                          details: won
                              ? [("Time", model.finalTime.clockString)] + (best.map { [("Best", $0.clockString)] } ?? [])
                              : [("Cleared", "\(model.percentCleared)%"), ("Time", model.finalTime.clockString)],
                          tint: won ? accent : MinePalette.exploded) {
                Button("Play Again") { withAnimation { model.newGame() } }
                    .buttonStyle(PrimaryButtonStyle(color: won ? accent : MinePalette.exploded))
                    .accessibilityIdentifier("playAgainButton")
                Button("View Board") { withAnimation(.easeOut(duration: 0.2)) { model.showResult = false } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        }
    }

    static let rules = HowToPlay(
        summary: "Uncover every safe square without setting off a mine.",
        sections: [
            .init(title: "Revealing", symbol: "hand.tap", points: [
                "Tap a square to reveal it. Your first tap is always safe and opens an area.",
                "A number tells you how many mines touch that square, including diagonals.",
                "Empty squares open up their neighbors automatically.",
            ]),
            .init(title: "Flagging", symbol: "flag.fill", points: [
                "Long-press a square to plant a flag where you think a mine is.",
                "Or switch to Flag mode at the bottom for one-handed play — then a long press reveals.",
                "Tap a number whose mines are all flagged to reveal the rest of its neighbors.",
            ]),
            .init(title: "Big boards", symbol: "plus.magnifyingglass", points: [
                "Pinch to zoom and drag to move around, or use the Zoom button.",
                "Clear every safe square to win. Your best time is kept for each level.",
            ]),
        ]
    )
}

/// Two-segment Reveal / Flag switch sized for thumbs; tapping anywhere flips it.
private struct ModeToggle: View {
    @Binding var mode: MinesweeperModel.Mode
    @Namespace private var pill

    var body: some View {
        Button(action: switchMode) {
            HStack(spacing: 4) {
                segment(.reveal, title: "Reveal", symbol: "hand.tap.fill", tint: MinePalette.accent)
                segment(.flag, title: "Flag", symbol: "flag.fill", tint: MinePalette.flag)
            }
            .padding(4)
            .background(Theme.well, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityLabel("Tap mode")
        .accessibilityValue(mode == .reveal ? "Reveal" : "Flag")
        .accessibilityHint("Switches between revealing and flagging squares")
        .accessibilityIdentifier("modeToggle")
    }

    private func switchMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = mode.toggled }
        Feedback.play(.select)
    }

    private func segment(_ value: MinesweeperModel.Mode, title: String, symbol: String, tint: Color) -> some View {
        let selected = mode == value
        return Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? .white : .secondary)
            .background {
                if selected {
                    Capsule().fill(tint).matchedGeometryEffect(id: "pill", in: pill)
                }
            }
    }
}
