import SwiftUI
import GameLogic

struct BlockPuzzleView: View {
    typealias Logic = BlockPuzzle

    @State private var model = BlockPuzzleModel()
    @State private var drag: PieceDrag?
    @State private var boardFrame: CGRect = .zero
    @State private var slotFrames: [Int: CGRect] = [:]
    /// True while a tray drag gesture is live; resets on its own if the system cancels it.
    @GestureState private var gestureActive = false
    @Environment(\.reduceMotion) private var reduceMotion

    nonisolated private static let space = "blockPuzzle"
    /// Tray pieces are drawn at this fraction of a board cell.
    private static let trayScale: CGFloat = 0.5

    /// A piece being dragged out of the tray.
    private struct PieceDrag {
        var slot: Int
        var piece: Logic.Piece
        /// Finger location in the game's coordinate space.
        var location: CGPoint
        /// Offset from the finger to the tray piece's center when the drag began.
        var grab: CGSize
        var lifted = false
        var ghost: GridPoint?
        var returning = false
        var moved = false
    }

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            VStack(spacing: layout.spacing) {
                header
                    .frame(maxWidth: layout.side)
                Spacer(minLength: 0)
                board(layout)
                Spacer(minLength: 0)
                tray(layout)
                controls
            }
            .padding(.horizontal, Layout.margin)
            .padding(.vertical, Layout.vMargin)
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topLeading) { floatingPiece(layout) }
        }
        .coordinateSpace(.named(Self.space))
        .onChange(of: gestureActive) { _, active in
            // A cancelled gesture never calls onEnded: send the piece home.
            if !active, drag != nil, drag?.returning == false {
                Task { @MainActor in
                    if drag != nil, drag?.returning == false { returnToTray() }
                }
            }
        }
        .overlay { overlay }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-hintDemo") { model.showHint() } }
        #endif
        .gameChrome(.blocks, rules: Self.rules,
                    stats: [StatsVariant(showsWins: false, showsScore: true)],
                    newGame: [NewGameOption(title: "New Game") { startNewGame() }],
                    onActiveChange: { active in
                        if !active { cancelDrag() }
                        model.setActive(active)
                    },
                    freshStart: { startNewGame() })
    }

    // MARK: Layout

    private struct Layout {
        static let margin: CGFloat = 20
        static let vMargin: CGFloat = 12
        let side: CGFloat
        let trayHeight: CGFloat
        let spacing: CGFloat
        var grid: BlockGrid { BlockGrid(side: side) }

        init(size: CGSize) {
            spacing = size.height < 640 ? 10 : 16
            let width = min(size.width - 2 * Self.margin, 600)
            // Header (~56) + controls (~64) + gaps.
            let fixed: CGFloat = 56 + 64 + 2 * Self.vMargin + 4 * spacing
            let trayRatio: CGFloat = 0.34
            side = max(220, min(width, (size.height - fixed) / (1 + trayRatio)))
            trayHeight = side * trayRatio
        }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 10) {
            CountingScorePill(title: "Score", value: Double(model.state.score), actual: model.state.score,
                              tint: GameID.blocks.accent)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: model.state.score)
                .accessibilityIdentifier("blocksScore")
            StatPill(title: "Best", value: "\(model.best)")
            Spacer(minLength: 0)
            if model.state.streak >= 2 {
                Label("×\(model.state.streak)", systemImage: "flame.fill")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(LinearGradient(colors: [Color(hex: 0xFFB347), Color(hex: 0xFF5E3A)],
                                               startPoint: .top, endPoint: .bottom), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Streak \(model.state.streak)")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.state.streak)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward",
                       badge: model.undosLeft > 0 ? "\(model.undosLeft)" : nil,
                       tint: GameID.blocks.accent) {
                cancelDrag()
                model.undo()
            }
            .disabled(!model.canUndo)
            .accessibilityValue("\(model.undosLeft) left")
            ToolButton(title: "Hint", systemImage: "lightbulb", isActive: model.hint != nil || model.isThinking,
                       tint: HintCard.amber) {
                cancelDrag()
                model.showHint()
            }
            .disabled(model.isOver)
            .accessibilityHint("Shows a good place for one of your pieces.")
            ToolButton(title: "New", systemImage: "arrow.clockwise", tint: GameID.blocks.accent) {
                startNewGame()
            }
        }
    }

    private func startNewGame() {
        cancelDrag()
        withAnimation(.easeOut(duration: 0.2)) { model.newGame() }
    }

    // MARK: Board

    private func board(_ layout: Layout) -> some View {
        let grid = layout.grid
        let ghost: (piece: Logic.Piece, origin: GridPoint)? = drag.flatMap { d in
            d.ghost.map { (d.piece, $0) }
        } ?? hintGhost
        return BlockBoardView(model: model, grid: grid, ghost: ghost, reduceMotion: reduceMotion)
            .overlay { if drag == nil { hintOutline(grid) } }
            .overlay { cellTargets(grid) }
            .frame(width: layout.side, height: layout.side)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { boardFrame = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Board")
            .accessibilityIdentifier("blocksBoard")
    }

    /// The hinted piece where it should go (only while nothing is being dragged).
    private var hintGhost: (piece: Logic.Piece, origin: GridPoint)? {
        guard drag == nil, let hint = model.hint, let piece = model.piece(in: hint.slot) else { return nil }
        return (piece, hint.origin)
    }

    /// An amber outline around the hinted spot, on top of the ghost.
    @ViewBuilder
    private func hintOutline(_ grid: BlockGrid) -> some View {
        if let ghost = hintGhost, let hint = model.hint {
            ZStack(alignment: .topLeading) {
                ForEach(ghost.piece.cells(at: ghost.origin), id: \.self) { p in
                    RoundedRectangle(cornerRadius: grid.cell * 0.22, style: .continuous)
                        .strokeBorder(HintCard.amber, lineWidth: max(2, grid.cell * 0.07))
                        .frame(width: grid.cell, height: grid.cell)
                        .position(grid.center(p))
                }
            }
            .frame(width: grid.side, height: grid.side)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement()
            .accessibilityLabel("Hint")
            .accessibilityValue(BlockPuzzleModel.describe(hint, piece: ghost.piece))
            .accessibilityIdentifier("hintGhost")
        }
    }

    /// Invisible per-cell targets: tap-to-place for everyone and VoiceOver cells.
    private func cellTargets(_ grid: BlockGrid) -> some View {
        let board = model.state.board
        let selected = model.selectedSlot.flatMap { model.piece(in: $0) }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<Logic.size * Logic.size, id: \.self) { i in
                let p = GridPoint(row: i / Logic.size, col: i % Logic.size)
                Color.clear
                    .frame(width: grid.step, height: grid.step)
                    .contentShape(Rectangle())
                    .position(grid.center(p))
                    .onTapGesture { model.tapCell(p) }
                    .accessibilityElement()
                    .accessibilityLabel("Row \(p.row + 1), column \(p.col + 1)")
                    .accessibilityValue(cellValue(p, board: board, selected: selected))
                    .accessibilityAddTraits(selected != nil ? .isButton : [])
                    .accessibilityHint(selected != nil ? "Places the selected piece centered here." : "")
                    .accessibilityIdentifier("cell.\(p.row).\(p.col)")
                    .accessibilityAction { model.tapCell(p) }
            }
        }
        .frame(width: grid.side, height: grid.side)
    }

    private func cellValue(_ p: GridPoint, board: Logic.Board, selected: Logic.Piece?) -> String {
        var value = board[p] == nil ? "Empty" : "Filled"
        if let selected {
            let origin = selected.origin(centeredOn: p)
            if let lines = board.linesCompleted(by: selected, at: origin) {
                let n = lines.rows.count + lines.cols.count
                value += n > 0 ? ". Piece fits, clears \(n) \(n == 1 ? "line" : "lines")" : ". Piece fits"
            } else {
                value += ". Piece doesn't fit"
            }
        }
        return value
    }

    // MARK: Tray

    private func tray(_ layout: Layout) -> some View {
        let grid = layout.grid
        let trayIDs = model.state.tray.map { $0?.id ?? -1 }
        return HStack(spacing: 0) {
            ForEach(0..<Logic.traySize, id: \.self) { slot in
                traySlot(slot, grid: grid)
            }
        }
        .frame(width: layout.side, height: layout.trayHeight)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .top) {
            if model.selectedSlot != nil {
                Text("Tap the board to place")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameID.blocks.accent)
                    .padding(.top, 6)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.7), value: trayIDs)
        .animation(.easeOut(duration: 0.15), value: model.selectedSlot)
    }

    private func traySlot(_ slot: Int, grid: BlockGrid) -> some View {
        let piece = model.piece(in: slot)
        let fits = model.state.canPlaceAnywhere(slot: slot)
        let selected = model.selectedSlot == slot
        let hidden = drag?.slot == slot
        let hinted = model.hint?.slot == slot && drag == nil
        return ZStack {
            if hinted && !selected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HintCard.amber.opacity(0.14))
                    .strokeBorder(HintCard.amber.opacity(0.8), lineWidth: 2)
                    .padding(6)
                    .transition(.opacity)
            }
            if selected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GameID.blocks.accent.opacity(0.14))
                    .strokeBorder(GameID.blocks.accent.opacity(0.7), lineWidth: 2)
                    .padding(6)
            }
            if let piece, !hidden {
                PieceView(piece: piece, cell: grid.cell * Self.trayScale, gap: grid.gap * Self.trayScale)
                    .saturation(fits ? 1 : 0.15)
                    .opacity(fits ? 1 : 0.45)
                    .scaleEffect(selected ? 1.08 : 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .id(piece.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slotFrames[slot] = $0 }
        .gesture(dragGesture(slot: slot, grid: grid))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(piece.map { Self.describe($0) } ?? "Empty slot")
        .accessibilityValue(piece == nil ? "" : fits ? (selected ? "Selected" : hinted ? "Hinted" : "") : "Doesn't fit anywhere")
        .accessibilityAddTraits(piece != nil ? [.isButton] : [])
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(piece != nil ? "Selects this piece, then choose a board cell." : "")
        .accessibilityIdentifier("traySlot.\(slot)")
        .accessibilityAction { model.select(slot: slot) }
    }

    // MARK: Dragging

    private func liftOffset(_ piece: Logic.Piece, grid: BlockGrid) -> CGFloat {
        BlockGrid.pieceSize(piece, cell: grid.cell, gap: grid.gap).height / 2 + grid.cell * 0.9
    }

    private func dragGesture(slot: Int, grid: BlockGrid) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !model.isOver, let piece = model.piece(in: slot) else { return }
                if drag == nil || drag?.slot != slot || drag?.returning == true {
                    let center = slotFrames[slot].map { CGPoint(x: $0.midX, y: $0.midY) } ?? value.startLocation
                    drag = PieceDrag(slot: slot, piece: piece, location: value.location,
                                     grab: CGSize(width: center.x - value.startLocation.x,
                                                  height: center.y - value.startLocation.y))
                    withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.26, dampingFraction: 0.72)) {
                        drag?.lifted = true
                    }
                    Haptics.tap()
                }
                guard var d = drag else { return }
                d.location = value.location
                if hypot(value.translation.width, value.translation.height) > 10 { d.moved = true }
                let ghost = ghostOrigin(for: piece, at: value.location, grid: grid)
                if ghost != d.ghost, ghost != nil { Haptics.select() }
                d.ghost = ghost
                drag = d
            }
            .onEnded { value in
                guard let d = drag, d.slot == slot, !d.returning else { return }
                if !d.moved {
                    returnToTray()
                    model.select(slot: slot)
                } else if let origin = d.ghost {
                    drag = nil
                    model.place(slot: slot, at: origin)
                } else {
                    let lifted = CGPoint(x: value.location.x, y: value.location.y - liftOffset(d.piece, grid: grid))
                    if boardFrame.insetBy(dx: -grid.cell, dy: -grid.cell).contains(lifted) {
                        Feedback.play(.invalid)
                    }
                    returnToTray()
                }
            }
    }

    private func ghostOrigin(for piece: Logic.Piece, at location: CGPoint, grid: BlockGrid) -> GridPoint? {
        guard boardFrame.width > 0 else { return nil }
        let size = BlockGrid.pieceSize(piece, cell: grid.cell, gap: grid.gap)
        let center = CGPoint(x: location.x, y: location.y - liftOffset(piece, grid: grid))
        let x = center.x - size.width / 2 - boardFrame.minX - grid.pad
        let y = center.y - size.height / 2 - boardFrame.minY - grid.pad
        return model.state.board.nearestValidOrigin(for: piece, row: Double(y / grid.step),
                                                    col: Double(x / grid.step), maxDistance: 0.85)
    }

    private func returnToTray() {
        guard var d = drag else { return }
        let frame = slotFrames[d.slot] ?? .zero
        d.ghost = nil
        drag = d
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.82)) {
            drag?.location = CGPoint(x: frame.midX, y: frame.midY)
            drag?.grab = .zero
            drag?.lifted = false
            drag?.returning = true
        }
        let slot = d.slot
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if drag?.slot == slot, drag?.returning == true { drag = nil }
        }
    }

    private func cancelDrag() {
        drag = nil
    }

    @ViewBuilder
    private func floatingPiece(_ layout: Layout) -> some View {
        if let d = drag {
            let grid = layout.grid
            PieceView(piece: d.piece, cell: grid.cell, gap: grid.gap)
                .shadow(color: .black.opacity(d.lifted ? 0.25 : 0), radius: 12, y: 10)
                .scaleEffect(d.lifted ? 1 : Self.trayScale)
                .offset(x: d.lifted ? 0 : d.grab.width,
                        y: d.lifted ? -liftOffset(d.piece, grid: grid) : d.grab.height)
                .position(d.location)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Overlay

    @ViewBuilder private var overlay: some View {
        if model.showGameOver {
            ResultOverlay(mood: model.isNewBest ? .win : .loss,
                          title: model.isNewBest ? "New Best!" : "Out of Room",
                          subtitle: model.isNewBest ? "You beat your best score." : "No piece fits on the board.",
                          details: [("Score", "\(model.state.score)"), ("Best", "\(model.best)"),
                                    ("Lines", "\(model.state.linesCleared)")],
                          tint: GameID.blocks.accent) {
                Button("Play Again") { startNewGame() }
                    .buttonStyle(PrimaryButtonStyle(color: GameID.blocks.accent))
                    .accessibilityIdentifier("playAgain")
            }
            .transition(.opacity)
        }
    }

    // MARK: Text

    static func describe(_ piece: Logic.Piece) -> String {
        let name: String = switch piece.family {
        case "dot": "Single block"
        case "domino": "Two-block bar"
        case "line3": "Three-block bar"
        case "line4": "Four-block bar"
        case "line5": "Five-block bar"
        case "corner3": "Small corner"
        case "corner5": "Big corner"
        case "square2": "Two by two square"
        case "square3": "Three by three square"
        case "rect": "Rectangle"
        case "L": "L piece"
        case "J": "J piece"
        case "T": "T piece"
        case "S": "S piece"
        case "Z": "Z piece"
        default: "Piece"
        }
        return "\(name), \(piece.cells.count) blocks, \(piece.width) wide by \(piece.height) tall"
    }

    static let rules = HowToPlay(
        summary: "Fit the pieces onto the board and clear full rows and columns.",
        sections: [
            .init(title: "Placing", symbol: "hand.draw", points: [
                "Drag a piece from the tray onto the board. A shadow shows where it will land.",
                "Or tap a piece to select it, then tap a cell on the board.",
                "Pieces can't be rotated. When all three are placed you get three new ones.",
            ]),
            .init(title: "Clearing", symbol: "sparkles", points: [
                "Fill a whole row or column and it clears. Rows and columns clear together.",
                "Clearing several lines at once scores a combo.",
                "Clear on consecutive placements to build a streak bonus. Empty the board for a big bonus.",
            ]),
            .init(title: "Game Over", symbol: "flag.checkered", points: [
                "The game ends when none of the remaining pieces fits anywhere.",
                "Grayed-out pieces don't fit right now.",
                "You can undo your last placement up to 3 times per game.",
                "Stuck? Tap Hint to see a good spot for one of your pieces. Hints are free and don't change your score.",
            ]),
            .init(title: "Tips", symbol: "lightbulb", points: [
                "Look at all three pieces before you place the first, and plan where each one will go.",
                "Keep a 3×3 space open for the big square, and a clear row or column for the long bars.",
                "Avoid leaving single empty squares boxed in: only a single block can fill them.",
                "Build along the edges and corners first and keep the middle open.",
                "Set up rows and columns that finish together: one piece clearing several lines scores a combo.",
            ]),
        ]
    )
}

/// A score pill whose number counts up smoothly.
private struct CountingScorePill: View, Animatable {
    let title: String
    var value: Double
    /// The real score, announced to VoiceOver while the number animates.
    let actual: Int
    var tint: Color

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint.opacity(0.9))
                .tracking(0.6)
            Text("\(Int(value.rounded()))")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(actual)")
    }
}
