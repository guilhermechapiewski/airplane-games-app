import SwiftUI
import GameLogic

// MARK: - Geometry

/// Board metrics shared by the board, the tray and the dragged piece.
struct BlockGrid {
    let side: CGFloat
    var pad: CGFloat { side * 0.028 }
    var gap: CGFloat { side * 0.011 }
    var cell: CGFloat { (side - 2 * pad - CGFloat(BlockPuzzle.size - 1) * gap) / CGFloat(BlockPuzzle.size) }
    var step: CGFloat { cell + gap }

    func center(_ p: GridPoint) -> CGPoint {
        CGPoint(x: pad + CGFloat(p.col) * step + cell / 2, y: pad + CGFloat(p.row) * step + cell / 2)
    }

    /// Converts fractional cell coordinates (0…8) into points.
    func point(_ cells: CGPoint) -> CGPoint {
        CGPoint(x: pad + cells.x * step - gap / 2, y: pad + cells.y * step - gap / 2)
    }

    static func pieceSize(_ piece: BlockPuzzle.Piece, cell: CGFloat, gap: CGFloat) -> CGSize {
        CGSize(width: CGFloat(piece.width) * cell + CGFloat(piece.width - 1) * gap,
               height: CGFloat(piece.height) * cell + CGFloat(piece.height - 1) * gap)
    }
}

// MARK: - Candy blocks

/// Original candy palette: cherry, tangerine, lemon, lime, aqua, sky, grape, bubblegum.
enum CandyPalette {
    struct Swatch {
        let light: Color
        let base: Color
        let dark: Color
    }

    static let swatches: [Swatch] = [
        Swatch(light: Color(hex: 0xFF8FA0), base: Color(hex: 0xFF4D66), dark: Color(hex: 0xD62845)),
        Swatch(light: Color(hex: 0xFFC27A), base: Color(hex: 0xFF9A33), dark: Color(hex: 0xE5730E)),
        Swatch(light: Color(hex: 0xFFEA8A), base: Color(hex: 0xFFCE2E), dark: Color(hex: 0xE5A800)),
        Swatch(light: Color(hex: 0xA6F08A), base: Color(hex: 0x5ED642), dark: Color(hex: 0x33A825)),
        Swatch(light: Color(hex: 0x7FF0E4), base: Color(hex: 0x22CFC0), dark: Color(hex: 0x0E9E93)),
        Swatch(light: Color(hex: 0x8CC4FF), base: Color(hex: 0x3D92FF), dark: Color(hex: 0x1F66DB)),
        Swatch(light: Color(hex: 0xC6A6FF), base: Color(hex: 0x9161FF), dark: Color(hex: 0x6A3BE0)),
        Swatch(light: Color(hex: 0xFFA8DC), base: Color(hex: 0xFF5CB8), dark: Color(hex: 0xDB3592)),
    ]

    static func swatch(_ index: Int) -> Swatch {
        swatches[((index % swatches.count) + swatches.count) % swatches.count]
    }
}

/// A single glossy, candy-like block.
struct CandyBlock: View {
    let color: Int
    let size: CGFloat
    var glow = false

    var body: some View {
        let s = CandyPalette.swatch(color)
        let radius = size * 0.24
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [s.light, s.base, s.dark],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.0), s.dark.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: max(1, size * 0.07))
            // Glossy highlight across the top.
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.66, height: size * 0.3)
                .offset(y: -size * 0.22)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.11, height: size * 0.11)
                .offset(x: -size * 0.26, y: -size * 0.25)
            if glow {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: s.dark.opacity(glow ? 0.9 : 0.35), radius: glow ? size * 0.25 : size * 0.05, y: glow ? 0 : size * 0.05)
    }
}

/// A polyomino drawn with candy blocks.
struct PieceView: View {
    let piece: BlockPuzzle.Piece
    let cell: CGFloat
    let gap: CGFloat

    var body: some View {
        let size = BlockGrid.pieceSize(piece, cell: cell, gap: gap)
        ZStack(alignment: .topLeading) {
            ForEach(piece.cells, id: \.self) { p in
                CandyBlock(color: piece.color, size: cell)
                    .offset(x: CGFloat(p.col) * (cell + gap), y: CGFloat(p.row) * (cell + gap))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Board

struct BlockBoardView: View {
    let model: BlockPuzzleModel
    let grid: BlockGrid
    /// The piece being dragged and where it would land.
    let ghost: (piece: BlockPuzzle.Piece, origin: GridPoint)?
    let reduceMotion: Bool

    var body: some View {
        let board = model.state.board
        let preview = ghost.flatMap { board.linesCompleted(by: $0.piece, at: $0.origin) }
        let clearing = Set(preview?.rows ?? []).isEmpty && Set(preview?.cols ?? []).isEmpty ? nil : preview
        let ghostCells = Set(ghost.map { $0.piece.cells(at: $0.origin) } ?? [])

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: grid.side * 0.045, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            RoundedRectangle(cornerRadius: grid.side * 0.045, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1)

            // Empty sockets.
            ForEach(0..<BlockPuzzle.size * BlockPuzzle.size, id: \.self) { i in
                RoundedRectangle(cornerRadius: grid.cell * 0.22, style: .continuous)
                    .fill(Theme.well)
                    .frame(width: grid.cell, height: grid.cell)
                    .position(grid.center(GridPoint(row: i / BlockPuzzle.size, col: i % BlockPuzzle.size)))
            }

            // Lines that would clear: a soft band in the piece's color.
            if let clearing, let ghost {
                let tint = CandyPalette.swatch(ghost.piece.color).base
                ForEach(clearing.rows, id: \.self) { r in
                    band(tint, horizontal: true, index: r)
                }
                ForEach(clearing.cols, id: \.self) { c in
                    band(tint, horizontal: false, index: c)
                }
            }

            // Placed blocks.
            ForEach(0..<BlockPuzzle.size * BlockPuzzle.size, id: \.self) { i in
                let p = GridPoint(row: i / BlockPuzzle.size, col: i % BlockPuzzle.size)
                if let color = board[p] {
                    let highlighted = clearing.map { $0.rows.contains(p.row) || $0.cols.contains(p.col) } ?? false
                    PlacedBlock(color: highlighted ? ghost!.piece.color : color,
                                size: grid.cell, glow: highlighted,
                                bounce: model.lastPlaced.contains(p) ? model.placementToken : 0,
                                reduceMotion: reduceMotion)
                        .position(grid.center(p))
                }
            }

            // Ghost preview.
            if let ghost {
                ForEach(Array(ghostCells), id: \.self) { p in
                    CandyBlock(color: ghost.piece.color, size: grid.cell)
                        .opacity(0.42)
                        .position(grid.center(p))
                }
            }

            // Clear effects.
            ForEach(model.bursts) { burst in
                ForEach(burst.cells, id: \.point) { c in
                    let dx = CGFloat(c.point.col) + 0.5 - burst.center.x
                    let dy = CGFloat(c.point.row) + 0.5 - burst.center.y
                    PoppingBlock(color: c.color, size: grid.cell,
                                 delay: reduceMotion ? 0 : Double((dx * dx + dy * dy).squareRoot()) * 0.035,
                                 reduceMotion: reduceMotion)
                        .position(grid.center(c.point))
                }
            }
            ForEach(model.floaters) { f in
                FloatingScore(floater: f, reduceMotion: reduceMotion, scale: grid.side / 360)
                    .position(grid.point(f.center))
            }
        }
        .frame(width: grid.side, height: grid.side)
        .animation(.easeOut(duration: 0.12), value: ghost?.origin)
    }

    private func band(_ tint: Color, horizontal: Bool, index: Int) -> some View {
        let length = grid.side - grid.pad
        let thickness = grid.cell + grid.gap
        let c = grid.center(horizontal ? GridPoint(row: index, col: 0) : GridPoint(row: 0, col: index))
        return RoundedRectangle(cornerRadius: grid.cell * 0.3, style: .continuous)
            .fill(tint.opacity(0.22))
            .frame(width: horizontal ? length : thickness, height: horizontal ? thickness : length)
            .position(horizontal ? CGPoint(x: grid.side / 2, y: c.y) : CGPoint(x: c.x, y: grid.side / 2))
    }
}

/// A block on the board, with a little squash when it lands.
private struct PlacedBlock: View {
    let color: Int
    let size: CGFloat
    let glow: Bool
    let bounce: Int
    let reduceMotion: Bool

    var body: some View {
        CandyBlock(color: color, size: size, glow: glow)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    if bounce != 0 && !reduceMotion {
                        CubicKeyframe(CGFloat(1.14), duration: 0.08)
                        SpringKeyframe(CGFloat(1), duration: 0.25, spring: .bouncy)
                        LinearKeyframe(CGFloat(1), duration: 0.05) // land exactly at rest
                    } else {
                        LinearKeyframe(CGFloat(1), duration: 0.01)
                    }
                }
            }
    }
}

/// A cleared block that swells, spins away and throws off sparkles.
private struct PoppingBlock: View {
    let color: Int
    let size: CGFloat
    let delay: Double
    let reduceMotion: Bool

    private struct Values {
        var scale: CGFloat = 1
        var opacity: Double = 1
        var spin: Double = 0
        var burst: CGFloat = 0
    }

    @State private var started = false

    var body: some View {
        let s = CandyPalette.swatch(color)
        CandyBlock(color: color, size: size)
        .keyframeAnimator(initialValue: Values(), trigger: started) { content, v in
            content
                .scaleEffect(v.scale)
                .rotationEffect(.degrees(v.spin))
                .opacity(v.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: delay)
                CubicKeyframe(1.2, duration: 0.09)
                CubicKeyframe(0.05, duration: reduceMotion ? 0.12 : 0.26)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: delay + 0.12)
                LinearKeyframe(0, duration: 0.24)
            }
            KeyframeTrack(\.spin) {
                LinearKeyframe(0, duration: delay + 0.06)
                CubicKeyframe(reduceMotion ? 0 : 35, duration: 0.3)
            }
        }
        .overlay {
            if !reduceMotion {
                SparkleSpray(color: s.light, size: size, delay: delay)
            }
        }
        .allowsHitTesting(false)
        .onAppear { started = true }
    }
}

/// Tiny stars flying out of a popped block.
private struct SparkleSpray: View {
    let color: Color
    let size: CGFloat
    let delay: Double
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let angle = Double(i) * .pi / 2 + .pi / 4
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.32, weight: .heavy))
                    .foregroundStyle(i.isMultiple(of: 2) ? .white : color)
                    .shadow(color: color.opacity(0.8), radius: 2)
                    .offset(x: out ? cos(angle) * size * 0.9 : 0, y: out ? sin(angle) * size * 0.9 : 0)
                    .scaleEffect(out ? 0.3 : 1)
                    .opacity(out ? 0 : 1)
            }
        }
        .opacity(out ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(delay + 0.08)) { out = true }
        }
    }
}

/// "+40" and "Combo ×2!" rising over the board.
private struct FloatingScore: View {
    let floater: BlockPuzzleModel.Floater
    let reduceMotion: Bool
    let scale: CGFloat
    @State private var shown = false
    @State private var gone = false

    var body: some View {
        let s = CandyPalette.swatch(floater.color)
        VStack(spacing: 0) {
            if let caption = floater.caption {
                Text(caption)
                    .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
            }
            Text("+\(floater.points)")
                .font(.system(size: 36 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(LinearGradient(colors: [s.base, s.dark], startPoint: .top, endPoint: .bottom))
        // A crisp white outline keeps the text readable over blocks in both themes.
        .shadow(color: .white, radius: 0, x: 1.5, y: 1.5)
        .shadow(color: .white, radius: 0, x: -1.5, y: -1.5)
        .shadow(color: .white, radius: 0, x: 1.5, y: -1.5)
        .shadow(color: .white, radius: 0, x: -1.5, y: 1.5)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .fixedSize()
        .scaleEffect(shown ? 1 : 0.5)
        .offset(y: reduceMotion ? 0 : (gone ? -50 * scale : shown ? -12 * scale : 10 * scale))
        .opacity(gone ? 0 : shown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shown = true }
            withAnimation(.easeIn(duration: 0.45).delay(0.75)) { gone = true }
        }
    }
}
