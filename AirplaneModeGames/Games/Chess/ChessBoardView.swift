import SwiftUI
import GameLogic

/// Warm wood board colours, tuned separately for light and dark appearance.
enum ChessTheme {
    static let lightSquare = Color(light: Color(hex: 0xF0DDBD), dark: Color(hex: 0xC9AD86))
    static let darkSquare = Color(light: Color(hex: 0xB78558), dark: Color(hex: 0x8A603F))
    static let frameTop = Color(light: Color(hex: 0x8E6040), dark: Color(hex: 0x5C3D27))
    static let frameBottom = Color(light: Color(hex: 0x5F3C23), dark: Color(hex: 0x3B2516))
    static let lastMove = Color(hex: 0xF5CF4F)
    static let selection = Color(hex: 0xF0B429)
    static let check = Color(hex: 0xE5383B)
    /// Hint squares and arrow: green, so they never read as the amber selection.
    static let hint = Color(hex: 0x2E9B57)
    static let accent = GameID.chess.accent
}

struct ChessBoardView: View {
    let model: ChessModel
    let side: CGFloat
    var reduceMotion = false

    @State private var dragFrom: Chess.Square?
    @State private var dragLocation: CGPoint?
    @State private var touchStarted = false
    @GestureState private var touchActive = false

    private var cell: CGFloat { side / 8 }
    private var whiteAtBottom: Bool { model.bottomSide == .white }

    var body: some View {
        ZStack(alignment: .topLeading) {
            squares
            pieces
            hintArrow
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: max(4, side * 0.012), style: .continuous))
        .contentShape(Rectangle())
        .gesture(boardGesture)
        .onGestureCancelled(touchActive) {
            // A cancelled drag puts the piece back without moving it.
            guard touchStarted || dragFrom != nil || dragLocation != nil else { return }
            withAnimation(moveAnimation) {
                dragFrom = nil
                dragLocation = nil
            }
            touchStarted = false
        }
        .overlay(alignment: .topLeading) { accessibilityGrid }
        .overlay { promotionPicker }
        .padding(max(5, side * 0.022))
        .background {
            RoundedRectangle(cornerRadius: max(8, side * 0.03), style: .continuous)
                .fill(LinearGradient(colors: [ChessTheme.frameTop, ChessTheme.frameBottom],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chess board")
        .accessibilityIdentifier("chessBoard")
    }

    // MARK: Geometry

    private func origin(of square: Chess.Square) -> CGPoint {
        let col = whiteAtBottom ? square.file : 7 - square.file
        let row = whiteAtBottom ? 7 - square.rank : square.rank
        return CGPoint(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
    }

    private func square(at point: CGPoint) -> Chess.Square? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return nil }
        let col = min(7, Int(point.x / cell)), row = min(7, Int(point.y / cell))
        return whiteAtBottom ? Chess.Square(file: col, rank: 7 - row) : Chess.Square(file: 7 - col, rank: row)
    }

    /// Squares in on-screen reading order (top-left first).
    private var displayOrder: [Chess.Square] {
        (0..<64).map { i in
            let col = i % 8, row = i / 8
            return whiteAtBottom ? Chess.Square(file: col, rank: 7 - row) : Chess.Square(file: 7 - col, rank: row)
        }
    }

    private var moveAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24)
    }

    // MARK: Layers

    private var squares: some View {
        let lastMove = model.game.lastMove
        let selected = model.selected
        let targets = model.targets
        let checked = model.checkedKing
        let hint = model.hint?.move
        let hover = dragLocation.flatMap { square(at: $0) }
        let position = model.position
        return Canvas { context, _ in
            let light = ChessTheme.lightSquare
            let dark = ChessTheme.darkSquare
            for sq in Chess.Square.all {
                let o = origin(of: sq)
                let rect = CGRect(x: o.x, y: o.y, width: cell, height: cell)
                context.fill(Path(rect), with: .color(sq.isLight ? light : dark))
                if let lastMove, sq == lastMove.from || sq == lastMove.to {
                    context.fill(Path(rect), with: .color(ChessTheme.lastMove.opacity(sq.isLight ? 0.5 : 0.45)))
                }
                if sq == selected {
                    context.fill(Path(rect), with: .color(ChessTheme.selection.opacity(0.62)))
                }
                if let hint, sq == hint.from || sq == hint.to {
                    context.fill(Path(rect), with: .color(ChessTheme.hint.opacity(0.32)))
                    let inset = cell * 0.04
                    context.stroke(Path(rect.insetBy(dx: inset, dy: inset)),
                                   with: .color(ChessTheme.hint.opacity(0.9)), lineWidth: cell * 0.07)
                }
                if sq == checked {
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    context.fill(Path(rect), with: .radialGradient(
                        Gradient(colors: [ChessTheme.check, ChessTheme.check.opacity(0.75), ChessTheme.check.opacity(0)]),
                        center: center, startRadius: 0, endRadius: cell * 0.72))
                }
            }
            // Legal destinations.
            for move in targets {
                let o = origin(of: move.to)
                let rect = CGRect(x: o.x, y: o.y, width: cell, height: cell)
                if position.piece(at: move.to) != nil {
                    let inset = cell * 0.06
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: inset + cell * 0.04, dy: inset + cell * 0.04)),
                                   with: .color(.black.opacity(0.28)), lineWidth: cell * 0.08)
                } else {
                    let r = cell * 0.15
                    context.fill(Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)),
                                 with: .color(.black.opacity(0.24)))
                }
            }
            if let hover, dragFrom != nil {
                let o = origin(of: hover)
                let rect = CGRect(x: o.x, y: o.y, width: cell, height: cell).insetBy(dx: cell * 0.03, dy: cell * 0.03)
                context.stroke(Path(rect), with: .color(.white.opacity(0.75)), lineWidth: cell * 0.06)
            }
            // Coordinates inside the edge squares.
            let fontSize = max(7, cell * 0.16)
            for i in 0..<8 {
                let fileSquare = displayOrder[56 + i] // bottom row
                let rankSquare = displayOrder[i * 8]  // left column
                let fo = origin(of: fileSquare)
                context.draw(Text(fileSquare.fileLetter)
                                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(fileSquare.isLight ? dark : light),
                             at: CGPoint(x: fo.x + cell - cell * 0.05, y: fo.y + cell - cell * 0.02),
                             anchor: .bottomTrailing)
                let ro = origin(of: rankSquare)
                context.draw(Text("\(rankSquare.rank + 1)")
                                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(rankSquare.isLight ? dark : light),
                             at: CGPoint(x: ro.x + cell * 0.05, y: ro.y + cell * 0.03),
                             anchor: .topLeading)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var pieces: some View {
        ForEach(model.tokens) { token in
            let dragging = token.square == dragFrom && dragLocation != nil
            let o = origin(of: token.square)
            let pos: CGPoint = dragging
                ? CGPoint(x: dragLocation!.x - cell / 2, y: dragLocation!.y - cell * 0.75)
                : o
            ChessPieceView(piece: token.piece, size: cell * 0.92)
                .frame(width: cell, height: cell)
                .scaleEffect(dragging ? 1.18 : 1, anchor: .bottom)
                .shadow(color: .black.opacity(dragging ? 0.3 : 0), radius: dragging ? 6 : 0, y: dragging ? 5 : 0)
                .offset(x: pos.x, y: pos.y)
                .zIndex(dragging ? 10 : (token.square == model.game.lastMove?.to ? 2 : 1))
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.2)),
                    removal: .scale(scale: 0.3).combined(with: .opacity)
                        .animation(.easeIn(duration: 0.18).delay(reduceMotion ? 0 : 0.1))))
                .allowsHitTesting(false)
        }
    }

    /// A translucent arrow from the hinted piece to its destination, drawn over the pieces.
    @ViewBuilder private var hintArrow: some View {
        if let move = model.hint?.move {
            let a = origin(of: move.from), b = origin(of: move.to)
            ChessArrow(from: CGPoint(x: a.x + cell / 2, y: a.y + cell / 2),
                       to: CGPoint(x: b.x + cell / 2, y: b.y + cell / 2), width: cell * 0.17)
                .fill(ChessTheme.hint.opacity(0.78))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .frame(width: side, height: side)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Input

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .tracking($touchActive)
            .onChanged { value in
                if !touchStarted {
                    touchStarted = true
                    if let sq = square(at: value.startLocation), model.canDrag(from: sq) {
                        dragFrom = sq
                    }
                }
                guard let from = dragFrom else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                if dragLocation == nil && distance < cell * 0.18 { return }
                if dragLocation == nil && model.selected != from { model.select(from) }
                dragLocation = value.location
            }
            .onEnded { value in
                defer { touchStarted = false }
                if let from = dragFrom, dragLocation != nil {
                    let target = square(at: value.location)
                    withAnimation(moveAnimation) {
                        dragFrom = nil
                        dragLocation = nil
                        if let target, target != from {
                            if !model.attemptMove(from: from, to: target) { model.clearSelection() }
                        }
                    }
                    return
                }
                dragFrom = nil
                dragLocation = nil
                if let sq = square(at: value.location) {
                    withAnimation(moveAnimation) { model.tap(sq) }
                }
            }
    }

    // MARK: Accessibility

    private var accessibilityGrid: some View {
        ForEach(displayOrder, id: \.self) { sq in
            let o = origin(of: sq)
            Color.clear
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
                .offset(x: o.x, y: o.y)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel(for: sq))
                .accessibilityValue(accessibilityValue(for: sq))
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(sq == model.selected ? .isSelected : [])
                .accessibilityIdentifier("square.\(sq.name)")
                .accessibilityAction {
                    withAnimation(moveAnimation) { model.tap(sq) }
                }
                .allowsHitTesting(false)
        }
    }

    private func accessibilityLabel(for sq: Chess.Square) -> String {
        if let piece = model.position.piece(at: sq) { return "\(sq.name), \(piece.name)" }
        return "\(sq.name), empty"
    }

    private func accessibilityValue(for sq: Chess.Square) -> String {
        var parts: [String] = []
        if sq == model.selected { parts.append("selected") }
        if model.targets.contains(where: { $0.to == sq }) {
            parts.append(model.position.piece(at: sq) != nil ? "can capture" : "can move here")
        }
        if sq == model.checkedKing { parts.append("in check") }
        if let hint = model.hint?.move {
            if sq == hint.from { parts.append("hint: move this piece") }
            if sq == hint.to { parts.append("hint: move here") }
        }
        if let last = model.game.lastMove, sq == last.from || sq == last.to { parts.append("last move") }
        return parts.joined(separator: ", ")
    }

    // MARK: Promotion

    @ViewBuilder private var promotionPicker: some View {
        if let pending = model.pendingPromotion {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .onTapGesture { withAnimation { model.cancelPromotion() } }
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("Promote to")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(Chess.PieceKind.promotions, id: \.self) { kind in
                            Button {
                                withAnimation(moveAnimation) { model.promote(to: kind) }
                            } label: {
                                ChessPieceView(piece: Chess.Piece(model.sideToMove, kind), size: min(64, cell * 1.05))
                                    .padding(6)
                                    .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(kind.name.capitalized)
                            .accessibilityIdentifier("promote.\(kind.name)")
                        }
                    }
                    Button("Cancel") { withAnimation { model.cancelPromotion() } }
                        .font(.subheadline.weight(.semibold))
                        .tint(ChessTheme.accent)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Promote pawn on \(pending.to.name)")
            }
            .transition(.opacity)
        }
    }
}

/// A straight arrow with a triangular head, from the centre of one square to another.
struct ChessArrow: Shape {
    let from: CGPoint
    let to: CGPoint
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 1 else { return Path() }
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let head = min(width * 2.6, length * 0.6)
        let start = CGPoint(x: from.x + ux * width * 0.8, y: from.y + uy * width * 0.8)
        let neck = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        let half = width / 2, wing = width * 1.35
        var p = Path()
        p.move(to: CGPoint(x: start.x + nx * half, y: start.y + ny * half))
        p.addLine(to: CGPoint(x: neck.x + nx * half, y: neck.y + ny * half))
        p.addLine(to: CGPoint(x: neck.x + nx * wing, y: neck.y + ny * wing))
        p.addLine(to: to)
        p.addLine(to: CGPoint(x: neck.x - nx * wing, y: neck.y - ny * wing))
        p.addLine(to: CGPoint(x: neck.x - nx * half, y: neck.y - ny * half))
        p.addLine(to: CGPoint(x: start.x - nx * half, y: start.y - ny * half))
        p.closeSubpath()
        return p
    }
}
