import SwiftUI
import GameLogic

struct SnakeView: View {
    typealias Logic = Snake

    @State private var model = SnakeModel()
    @AppStorage("snake.showDPad") private var showDPad = false
    @State private var swipeAnchor: CGPoint?
    @GestureState private var swipeActive = false
    @Environment(\.reduceMotion) private var reduceMotion

    private let accent = GameID.snake.accent

    var body: some View {
        GeometryReader { geo in
            let side = boardSide(in: geo.size)
            VStack(spacing: 14) {
                header
                    .frame(maxWidth: side)
                Spacer(minLength: 0)
                board(side: side)
                Spacer(minLength: 0)
                if showDPad {
                    DPad(tint: accent) { model.turn($0) }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Text("Swipe anywhere to steer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(width: geo.size.width, height: geo.size.height)
            // Swipe anywhere on the screen to steer; buttons and the D-pad keep their own touches.
            .contentShape(Rectangle())
            .gesture(swipe)
            .onGestureCancelled(swipeActive) { swipeAnchor = nil }
        }
        .overlay { overlay }
        .gameChrome(.snake, rules: Self.rules,
                    stats: Logic.Speed.allCases.map {
                        StatsVariant(key: $0.rawValue, title: $0.title, showsWins: false, showsScore: true)
                    },
                    newGame: newGameOptions,
                    onActiveChange: model.setActive,
                    swipeBack: .all,
                    freshStart: { model.newGame(autoStart: false) })
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space]) { press in
            switch press.key {
            case .upArrow: model.turn(.up)
            case .downArrow: model.turn(.down)
            case .leftArrow: model.turn(.left)
            case .rightArrow: model.turn(.right)
            default: model.togglePause()
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "wasdWASD")) { press in
            switch press.characters.lowercased() {
            case "w": model.turn(.up)
            case "s": model.turn(.down)
            case "a": model.turn(.left)
            default: model.turn(.right)
            }
            return .handled
        }
    }

    private func boardSide(in size: CGSize) -> CGFloat {
        let width = min(size.width - 40, 600)
        // Header (~56) + hint/D-pad + controls (~64) + gaps.
        let below: CGFloat = showDPad ? DPad.height : 20
        let height = size.height - 24 - 56 - below - 64 - 4 * 14
        return max(200, min(width, height))
    }

    private var newGameOptions: [NewGameOption] {
        var options = Logic.Speed.allCases.map { speed in
            NewGameOption(title: speed.title, systemImage: Self.symbol(for: speed)) {
                withAnimation { model.newGame(speed: speed, autoStart: false) }
            }
        }
        let wrapping = model.wallMode == .wrap
        options.append(NewGameOption(title: wrapping ? "Switch to Walls" : "Switch to Wrap-Around",
                                     systemImage: wrapping ? "square" : "square.dashed") {
            withAnimation { model.newGame(wallMode: wrapping ? .walls : .wrap, autoStart: false) }
        })
        return options
    }

    static func symbol(for speed: Logic.Speed) -> String {
        switch speed {
        case .relaxed: "tortoise.fill"
        case .normal: "figure.walk"
        case .fast: "hare.fill"
        }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 10) {
            StatPill(title: "Score", value: "\(model.state.score)", tint: accent)
                .accessibilityIdentifier("snakeScore")
            StatPill(title: "Best", value: "\(model.best)")
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Label {
                    Text(model.speed.title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: Self.symbol(for: model.speed)).foregroundStyle(accent)
                }
                Text(model.wallMode == .wrap ? "Wrap-around" : "Walls")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .combine)
        }
        .animation(.snappy, value: model.state.score)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            let paused = model.phase == .paused || model.phase == .ready
            ToolButton(title: paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill", tint: accent) {
                model.togglePause()
            }
            .disabled(model.phase == .over)
            .accessibilityIdentifier("snakePause")
            ToolButton(title: "D-Pad", systemImage: "dpad.fill", isActive: showDPad, tint: accent) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showDPad.toggle() }
            }
            ToolButton(title: "New", systemImage: "arrow.clockwise", tint: accent) {
                withAnimation { model.newGame(autoStart: false) }
            }
        }
    }

    // MARK: Board

    private func board(side: CGFloat) -> some View {
        SnakeBoardView(model: model, reduceMotion: reduceMotion)
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            .overlay {
                boardOverlay
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.7),
                               value: model.phase)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Snake board")
            .accessibilityValue(accessibilityValue)
            .accessibilityAction(named: "Up") { model.turn(.up) }
            .accessibilityAction(named: "Down") { model.turn(.down) }
            .accessibilityAction(named: "Left") { model.turn(.left) }
            .accessibilityAction(named: "Right") { model.turn(.right) }
            .accessibilityIdentifier("snakeBoard")
    }

    /// Finger travel that counts as a swipe. Small enough to register within a frame or two of
    /// a flick, large enough that a resting thumb's jitter doesn't steer.
    private static let swipeThreshold: CGFloat = 12

    /// Turns as soon as the finger has travelled far enough, so one continuous swipe can
    /// chain several turns (e.g. a quick U-turn).
    private var swipe: some Gesture {
        // Below the threshold so it never delays a turn, but nonzero so overlay buttons still get taps.
        DragGesture(minimumDistance: 6)
            .tracking($swipeActive)
            .onChanged { value in
                let anchor = swipeAnchor ?? value.startLocation
                let dx = value.location.x - anchor.x, dy = value.location.y - anchor.y
                guard max(abs(dx), abs(dy)) > Self.swipeThreshold else {
                    if swipeAnchor == nil { swipeAnchor = anchor }
                    return
                }
                let dir: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                model.turn(dir)
                swipeAnchor = value.location
            }
            .onEnded { _ in swipeAnchor = nil }
    }

    private var accessibilityValue: String {
        let s = model.state
        var parts = ["Score \(s.score)", "Length \(s.length)", "Heading \(s.direction.rawValue)"]
        if let food = s.food {
            let dr = food.row - s.head.row, dc = food.col - s.head.col
            var where_: [String] = []
            if dr != 0 { where_.append("\(abs(dr)) \(dr < 0 ? "up" : "down")") }
            if dc != 0 { where_.append("\(abs(dc)) \(dc < 0 ? "left" : "right")") }
            if !where_.isEmpty { parts.append("Food " + where_.joined(separator: ", ")) }
        }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder private var boardOverlay: some View {
        switch model.phase {
        case .ready:
            ReadyCard(model: model, accent: accent)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: accent.opacity(0.8), radius: 0, y: 4)
                .shadow(color: .black.opacity(0.25), radius: 10)
                .id(n)
                .transition(reduceMotion ? .opacity : .scale(scale: 1.6).combined(with: .opacity))
                .accessibilityLabel("Starting in \(n)")
        case .paused:
            VStack(spacing: 14) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(accent)
                Text("Paused")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                Text("Score \(model.state.score) · Length \(model.state.length)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Resume") { model.play() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("snakeResume")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .transition(.opacity)
        default:
            EmptyView()
        }
    }

    // MARK: Game over

    @ViewBuilder private var overlay: some View {
        if model.showGameOver {
            let won = model.state.status == .won
            ResultOverlay(mood: won || model.isNewBest ? .win : .loss,
                          title: won ? "Board Cleared!" : model.isNewBest ? "New Best!" : "Game Over",
                          subtitle: subtitle,
                          details: [("Score", "\(model.state.score)"), ("Best", "\(model.best)"),
                                    ("Length", "\(model.state.length)")],
                          tint: accent) {
                Button("Play Again") { withAnimation { model.newGame(autoStart: true) } }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("playAgain")
                Button("Change Speed") { withAnimation { model.newGame(autoStart: false) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        }
    }

    private var subtitle: String {
        if model.state.status == .won { return "Every cell is snake. Incredible!" }
        switch model.state.deathCause {
        case .wall: return "You hit the wall."
        case .selfCollision: return "You bit your own tail."
        case nil: return ""
        }
    }

    static let rules = HowToPlay(
        summary: "Guide the snake to the berries. Every berry makes it longer.",
        sections: [
            .init(title: "Steering", symbol: "hand.draw", points: [
                "Swipe anywhere on the board to turn. You can't reverse straight into yourself.",
                "Prefer buttons? Turn on the D-pad. On iPad, use the arrow keys (space pauses).",
                "Quick turns are remembered, so you can swipe twice for a tight U-turn.",
            ]),
            .init(title: "Scoring", symbol: "star.fill", points: [
                "Each berry is worth one point and grows the snake by one.",
                "Fill the whole board to win. Best scores are kept for each speed.",
            ]),
            .init(title: "Options", symbol: "slider.horizontal.3", points: [
                "Relaxed, Normal or Fast — choose before you start or from New Game.",
                "Walls: touching the edge ends the game. Wrap-around: you come out the other side.",
                "The game pauses when you leave and resumes after a 3-2-1 countdown.",
            ]),
        ]
    )
}

/// Pre-game card: pick speed and edges, then play.
private struct ReadyCard: View {
    let model: SnakeModel
    let accent: Color

    var body: some View {
        VStack(spacing: 14) {
            GameBadge(game: .snake, size: 52)
            Picker("Speed", selection: Binding(get: { model.speed }, set: { model.configure(speed: $0) })) {
                ForEach(Snake.Speed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            Picker("Edges", selection: Binding(get: { model.wallMode }, set: { model.configure(wallMode: $0) })) {
                Text("Walls").tag(Snake.WallMode.walls)
                Text("Wrap-Around").tag(Snake.WallMode.wrap)
            }
            .pickerStyle(.segmented)
            Button("Play") { model.play() }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("snakePlay")
            Text("or swipe to start")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(16)
    }
}

/// On-screen direction pad. Buttons fire on touch-down for responsiveness.
private struct DPad: View {
    static let height: CGFloat = 150
    let tint: Color
    let action: (Direction) -> Void

    var body: some View {
        let b: CGFloat = 52
        VStack(spacing: 0) {
            PadButton(direction: .up, size: b, tint: tint, action: action)
            HStack(spacing: b * 0.9) {
                PadButton(direction: .left, size: b, tint: tint, action: action)
                PadButton(direction: .right, size: b, tint: tint, action: action)
            }
            PadButton(direction: .down, size: b, tint: tint, action: action)
        }
        .frame(height: Self.height)
    }
}

private struct PadButton: View {
    let direction: Direction
    let size: CGFloat
    let tint: Color
    let action: (Direction) -> Void
    @State private var pressed = false
    @GestureState private var touchActive = false

    private var symbol: String {
        switch direction {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(pressed ? .white : tint)
            .frame(width: size, height: size)
            .background(pressed ? tint : Theme.surface, in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .tracking($touchActive)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        Haptics.tap()
                        action(direction)
                    }
                    .onEnded { _ in pressed = false }
            )
            .onGestureCancelled(touchActive) { pressed = false }
            .accessibilityElement()
            .accessibilityLabel(direction.rawValue.capitalized)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(direction) }
    }
}
