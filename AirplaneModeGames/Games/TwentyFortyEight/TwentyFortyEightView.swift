import SwiftUI
import GameLogic

struct TwentyFortyEightView: View {
    @State private var model = TwentyFortyEightModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            board
            Spacer(minLength: 0)
            controls
        }
        .padding(20)
        .overlay { overlay }
        .gameChrome(.twentyFortyEight, rules: Self.rules,
                    stats: [StatsVariant(showsScore: true)],
                    newGame: [NewGameOption(title: "New Game") { withAnimation { model.newGame() } }],
                    onActiveChange: model.setActive)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.move(.up); return .handled }
        .onKeyPress(.downArrow) { model.move(.down); return .handled }
        .onKeyPress(.leftArrow) { model.move(.left); return .handled }
        .onKeyPress(.rightArrow) { model.move(.right); return .handled }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatPill(title: "Score", value: "\(model.state.score)", tint: GameID.twentyFortyEight.accent)
            StatPill(title: "Best", value: "\(model.best)")
            Spacer()
        }
        .animation(.snappy, value: model.state.score)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward",
                       badge: model.history.isEmpty ? nil : "\(model.history.count)") {
                withAnimation(.easeOut(duration: 0.12)) { model.undo() }
            }
            .disabled(!model.canUndo)
            ToolButton(title: "New", systemImage: "arrow.clockwise") {
                withAnimation { model.newGame() }
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            BoardView(model: model, side: side, reduceMotion: reduceMotion)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 520)
        .gesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard max(abs(dx), abs(dy)) > 24 else { return }
                    let dir: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    model.move(dir)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAction(named: "Swipe up") { model.move(.up) }
        .accessibilityAction(named: "Swipe down") { model.move(.down) }
        .accessibilityAction(named: "Swipe left") { model.move(.left) }
        .accessibilityAction(named: "Swipe right") { model.move(.right) }
        .accessibilityIdentifier("board2048")
    }

    private var accessibilityDescription: String {
        let rows = model.state.valueGrid.enumerated().map { i, row in
            "Row \(i + 1): " + row.map { $0 == 0 ? "empty" : "\($0)" }.joined(separator: ", ")
        }
        return "Board. Score \(model.state.score). " + rows.joined(separator: ". ")
    }

    @ViewBuilder private var overlay: some View {
        if model.showWin {
            ResultOverlay(mood: .win, title: "2048!", subtitle: "You reached the 2048 tile.",
                          details: [("Score", "\(model.state.score)"), ("Time", model.clock.elapsed().clockString)],
                          tint: GameID.twentyFortyEight.accent) {
                Button("Keep Going") { model.continueAfterWin() }
                    .buttonStyle(PrimaryButtonStyle(color: GameID.twentyFortyEight.accent))
                Button("New Game") { withAnimation { model.newGame() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        } else if model.isOver {
            ResultOverlay(mood: model.state.hasWon ? .win : .loss,
                          title: "No more moves",
                          subtitle: model.state.score >= model.best ? "New best score!" : "Highest tile: \(model.state.highestTile)",
                          details: [("Score", "\(model.state.score)"), ("Best", "\(model.best)")],
                          tint: GameID.twentyFortyEight.accent) {
                Button("Play Again") { withAnimation { model.newGame() } }
                    .buttonStyle(PrimaryButtonStyle(color: GameID.twentyFortyEight.accent))
            }
            .transition(.opacity)
        }
    }

    static let rules = HowToPlay(
        summary: "Slide the tiles and merge equal numbers to build a 2048 tile.",
        sections: [
            .init(title: "Moving", symbol: "hand.draw", points: [
                "Swipe up, down, left or right. Every tile slides as far as it can.",
                "After each move a new 2 (or sometimes 4) appears in an empty spot.",
                "On iPad with a keyboard, use the arrow keys.",
            ]),
            .init(title: "Merging", symbol: "plus.square.on.square", points: [
                "Two tiles with the same number merge into one with their sum.",
                "A tile can merge only once per move.",
                "Each merge adds the new tile's value to your score.",
            ]),
            .init(title: "Winning", symbol: "trophy", points: [
                "Create a 2048 tile to win — then keep going for a higher score.",
                "The game ends when the board is full and no merges are possible.",
                "Made a mistake? Undo up to 20 moves.",
            ]),
        ]
    )
}

private struct BoardView: View {
    let model: TwentyFortyEightModel
    let side: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let n = model.state.size
        let spacing = side * 0.025
        let cell = (side - spacing * CGFloat(n + 1)) / CGFloat(n)
        let tiles = model.ghosts.map { (tile: $0, ghost: true) } + model.state.tiles.map { (tile: $0, ghost: false) }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                .fill(Theme.well)
            ForEach(0..<n * n, id: \.self) { i in
                RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                    .fill(Theme.surface.opacity(0.55))
                    .frame(width: cell, height: cell)
                    .offset(x: spacing + CGFloat(i % n) * (cell + spacing),
                            y: spacing + CGFloat(i / n) * (cell + spacing))
            }
            ForEach(tiles, id: \.tile.id) { entry in
                TileView(value: entry.tile.value, size: cell,
                         pop: model.mergedIDs.contains(entry.tile.id) ? model.moveCount : 0,
                         reduceMotion: reduceMotion)
                    .offset(x: spacing + CGFloat(entry.tile.position.col) * (cell + spacing),
                            y: spacing + CGFloat(entry.tile.position.row) * (cell + spacing))
                    .zIndex(entry.ghost ? 0 : 1)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7).delay(0.08)),
                        removal: .identity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.moveCount)
    }
}

private struct TileView: View {
    let value: Int
    let size: CGFloat
    /// Changes to a new non-zero value whenever this tile should pop.
    let pop: Int
    let reduceMotion: Bool

    var body: some View {
        let style = TileStyle(value: value)
        let peak: CGFloat = (pop != 0 && !reduceMotion) ? 1.14 : 1.0
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(style.fill)
            .overlay {
                Text("\(value)")
                    .font(.system(size: size * style.fontScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(style.text)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(size * 0.08)
            }
            .shadow(color: style.glow, radius: value >= 1024 ? size * 0.18 : 0)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: pop) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(CGFloat(1), duration: 0.1)
                    SpringKeyframe(peak, duration: 0.08)
                    SpringKeyframe(CGFloat(1), duration: 0.14)
                }
            }
    }
}

/// Original color ramp for tile values.
private struct TileStyle {
    let fill: AnyShapeStyle
    let text: Color
    let glow: Color
    let fontScale: CGFloat

    init(value: Int) {
        let digits = String(value).count
        fontScale = digits <= 2 ? 0.46 : digits == 3 ? 0.38 : digits == 4 ? 0.3 : 0.24
        let colors: [Int: (UInt32, UInt32)] = [
            2: (0xF3F0FF, 0xE6E0FF), 4: (0xE3ECFF, 0xCFDDFF),
            8: (0xFFC86B, 0xFFAE3D), 16: (0xFFA65C, 0xFF8538),
            32: (0xFF7F6B, 0xFF5C4D), 64: (0xFF5A72, 0xE8384F),
            128: (0xB892FF, 0x9A6BFF), 256: (0x8E7BFF, 0x6C55F0),
            512: (0x6E9DFF, 0x4675F0), 1024: (0x4AD995, 0x22B36F),
            2048: (0xFFE07A, 0xFFB800),
        ]
        if let pair = colors[value] {
            fill = AnyShapeStyle(LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)],
                                                startPoint: .top, endPoint: .bottom))
        } else {
            fill = AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3B4157), Color(hex: 0x23273A)],
                                                startPoint: .top, endPoint: .bottom))
        }
        text = value <= 4 ? Color(hex: 0x4A4A6A) : .white
        glow = value >= 2048 ? Color(hex: 0xFFC400).opacity(0.7) : value >= 1024 ? Color(hex: 0x22B36F).opacity(0.5) : .clear
    }
}
